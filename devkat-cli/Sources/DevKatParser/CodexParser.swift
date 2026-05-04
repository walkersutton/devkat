import Foundation

// MARK: - Codex session discovery

/// Reads sessions from ~/.codex/state_5.sqlite, parses each rollout JSONL
/// for line-level diff stats, then returns ParsedSession values.

public enum CodexParseError: Error {
    case sqliteNotFound(String)
    case noSessionsFound
}

// Minimal SQLite3 wrapper using the system dylib (no SPM dependency needed)
import SQLite3

public func findAllCodexSessions(in codexDir: URL, since cutoff: Date = Date(timeIntervalSince1970: 0)) -> [CodexThreadRow] {
    let dbPath = codexDir.appendingPathComponent("state_5.sqlite").path
    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
        return []
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 5000)

    let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)
    let sql = """
        SELECT id, rollout_path, created_at_ms, updated_at_ms,
               tokens_used, cwd, git_branch, model, model_provider
        FROM threads
        WHERE tokens_used > 0 AND has_user_event = 0
          AND updated_at_ms >= \(cutoffMs)
        ORDER BY updated_at_ms DESC
        """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }

    var rows: [CodexThreadRow] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        func text(_ col: Int32) -> String? {
            sqlite3_column_text(stmt, col).map { String(cString: $0) }
        }
        func int64(_ col: Int32) -> Int64 { sqlite3_column_int64(stmt, col) }

        guard let id = text(0), let rollout = text(1) else { continue }
        rows.append(CodexThreadRow(
            id: id,
            rolloutPath: rollout,
            createdAtMs: int64(2),
            updatedAtMs: int64(3),
            tokensUsed: Int(int64(4)),
            cwd: text(5),
            gitBranch: text(6),
            model: text(7) ?? "codex",
            modelProvider: text(8) ?? "openai"
        ))
    }
    return rows
}

public struct CodexThreadRow {
    public let id: String
    public let rolloutPath: String
    public let createdAtMs: Int64
    public let updatedAtMs: Int64
    public let tokensUsed: Int
    public let cwd: String?
    public let gitBranch: String?
    public let model: String
    public let modelProvider: String
}

public func findLatestCodexSession(in codexDir: URL) -> CodexThreadRow? {
    findAllCodexSessions(in: codexDir).first
}

// MARK: - Rollout JSONL parsing (lines added/removed/files)

private struct CodexEvent: Decodable {
    let type: String
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let type: String?
    let command: [String]?
    let aggregated_output: String?
    let parsed_cmd: [CodexParsedCmd]?
}

private struct CodexParsedCmd: Decodable {
    let type: String?
    let path: String?
}

public struct CodexDiffStats {
    public var linesAdded: Int = 0
    public var linesRemoved: Int = 0
    public var filesTouched: Set<String> = []
}

public func parseCodexDiffStats(rolloutPath: String) -> CodexDiffStats {
    var stats = CodexDiffStats()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: rolloutPath)) else {
        return stats
    }

    let decoder = JSONDecoder()
    let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)

    for line in lines {
        guard let event = try? decoder.decode(CodexEvent.self, from: Data(line)),
              event.type == "event_msg",
              let p = event.payload,
              p.type == "exec_command_end"
        else { continue }

        let cmd = p.command ?? []

        // Track files from parsed_cmd read entries
        for pc in (p.parsed_cmd ?? []) {
            if let path = pc.path, !path.isEmpty, path != "." {
                stats.filesTouched.insert(path)
            }
        }

        // Count diff lines from git diff output
        let isGitDiff = cmd.contains(where: { $0.contains("git") }) &&
                        cmd.contains(where: { $0.contains("diff") })
        if isGitDiff, let out = p.aggregated_output {
            for diffLine in out.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(diffLine)
                if s.hasPrefix("+") && !s.hasPrefix("+++") { stats.linesAdded += 1 }
                else if s.hasPrefix("-") && !s.hasPrefix("---") { stats.linesRemoved += 1 }
                // Capture filenames: +++ b/path
                if s.hasPrefix("+++ b/") {
                    stats.filesTouched.insert(String(s.dropFirst(6)))
                }
            }
        }
    }
    return stats
}

// MARK: - Full session parse

/// Maximum inactivity gap before splitting into separate work sessions
private let codexMaxGapSeconds: TimeInterval = 4 * 3600 // 4 hours

public func parseCodexSession(_ row: CodexThreadRow) -> ParsedSession {
    return parseCodexSessions(row).last ?? makeCodexFallback(row)
}

/// Parses a Codex session, splitting into multiple sessions at 4-hour inactivity gaps.
public func parseCodexSessions(_ row: CodexThreadRow) -> [ParsedSession] {
    let diff = parseCodexDiffStats(rolloutPath: row.rolloutPath)
    let repoAlias = row.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

    let modelLabel: String
    if row.model.isEmpty || row.model == "codex" {
        modelLabel = row.modelProvider
    } else {
        modelLabel = "\(row.modelProvider)/\(row.model)"
    }

    // Try to get event timestamps from rollout JSONL for gap detection
    let eventTimestamps = parseCodexEventTimestamps(rolloutPath: row.rolloutPath)

    if eventTimestamps.count >= 2 {
        // Split on 4-hour gaps
        var splitIndices: [Int] = [0]
        for i in 1..<eventTimestamps.count {
            let gap = eventTimestamps[i].timeIntervalSince(eventTimestamps[i-1])
            if gap > codexMaxGapSeconds {
                splitIndices.append(i)
            }
        }

        if splitIndices.count == 1 {
            // No splits needed
            return [makeSingleCodexSession(row, diff: diff, repoAlias: repoAlias, modelLabel: modelLabel)]
        }

        // Proportionally distribute metrics across segments based on time
        let totalSpan = eventTimestamps.last!.timeIntervalSince(eventTimestamps.first!)
        var results: [ParsedSession] = []

        for (segIdx, startIdx) in splitIndices.enumerated() {
            let endIdx = segIdx + 1 < splitIndices.count ? splitIndices[segIdx + 1] : eventTimestamps.count
            let segStart = eventTimestamps[startIdx]
            let segEnd = eventTimestamps[endIdx - 1]
            let segSpan = segEnd.timeIntervalSince(segStart)
            let proportion = totalSpan > 0 ? segSpan / totalSpan : 1.0 / Double(splitIndices.count)

            let sessionId = "\(row.id)_seg\(segIdx)"

            results.append(ParsedSession(
                id: sessionId,
                startedAt: segStart,
                endedAt: segEnd,
                activeDuration: segSpan,
                linesAdded: Int(Double(diff.linesAdded) * proportion),
                linesRemoved: Int(Double(diff.linesRemoved) * proportion),
                filesTouched: diff.filesTouched.count,
                tokens: Int(Double(row.tokensUsed) * proportion),
                model: modelLabel,
                repoAlias: repoAlias,
                gitBranch: row.gitBranch,
                source: .codex
            ))
        }
        return results
    }

    return [makeSingleCodexSession(row, diff: diff, repoAlias: repoAlias, modelLabel: modelLabel)]
}

private func makeSingleCodexSession(_ row: CodexThreadRow, diff: CodexDiffStats, repoAlias: String?, modelLabel: String) -> ParsedSession {
    let startedAt = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
    let endedAt   = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000.0)
    return ParsedSession(
        id: row.id,
        startedAt: startedAt,
        endedAt: endedAt,
        activeDuration: endedAt.timeIntervalSince(startedAt),
        linesAdded: diff.linesAdded,
        linesRemoved: diff.linesRemoved,
        filesTouched: diff.filesTouched.count,
        tokens: row.tokensUsed,
        model: modelLabel,
        repoAlias: repoAlias,
        gitBranch: row.gitBranch,
        source: .codex
    )
}

private func makeCodexFallback(_ row: CodexThreadRow) -> ParsedSession {
    let diff = parseCodexDiffStats(rolloutPath: row.rolloutPath)
    let repoAlias = row.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
    let modelLabel = row.model.isEmpty ? row.modelProvider : "\(row.modelProvider)/\(row.model)"
    return makeSingleCodexSession(row, diff: diff, repoAlias: repoAlias, modelLabel: modelLabel)
}

/// Extracts event timestamps from a Codex rollout JSONL
private func parseCodexEventTimestamps(rolloutPath: String) -> [Date] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: rolloutPath)) else {
        return []
    }

    let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    var timestamps: [Date] = []
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    struct TimestampEvent: Decodable {
        let timestamp: String?
        let created_at: String?
    }

    let decoder = JSONDecoder()
    for line in lines {
        guard let event = try? decoder.decode(TimestampEvent.self, from: Data(line)) else { continue }
        if let ts = event.timestamp ?? event.created_at,
           let date = isoFormatter.date(from: ts) {
            timestamps.append(date)
        }
    }

    return timestamps.sorted()
}
