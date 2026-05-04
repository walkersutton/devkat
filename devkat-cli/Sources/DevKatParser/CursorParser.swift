import Foundation
import SQLite3

// MARK: - Cursor session discovery

/// Reads sessions from Cursor's globalStorage/state.vscdb.
/// Cursor stores composer session metadata in ItemTable under the key
/// "composer.composerHeaders" as JSON with an "allComposers" array.

private let cursorDBPath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
}()

public struct CursorComposerRow {
    public let composerId: String
    public let name: String
    public let createdAtMs: Int64
    public let updatedAtMs: Int64
    public let linesAdded: Int
    public let linesRemoved: Int
    public let filesChanged: Int
    public let repoPath: String?
    public let gitBranch: String?
    public let mode: String
}

public func findAllCursorSessions(since cutoff: Date = Date(timeIntervalSince1970: 0)) -> [CursorComposerRow] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(cursorDBPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
        return []
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 5000)

    let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000)

    let sql = "SELECT value FROM ItemTable WHERE key = 'composer.composerHeaders'"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }

    guard sqlite3_step(stmt) == SQLITE_ROW,
          let blob = sqlite3_column_text(stmt, 0)
    else { return [] }

    let jsonStr = String(cString: blob)
    guard let data = jsonStr.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let composers = root["allComposers"] as? [[String: Any]]
    else { return [] }

    var rows: [CursorComposerRow] = []
    for c in composers {
        guard let cid = c["composerId"] as? String,
              let createdAt = c["createdAt"] as? Int64,
              let mode = c["unifiedMode"] as? String,
              // Only include agent/edit sessions that actually changed code
              mode != "chat"
        else { continue }

        let linesAdded = c["totalLinesAdded"] as? Int ?? 0
        let linesRemoved = c["totalLinesRemoved"] as? Int ?? 0
        let filesChanged = c["filesChangedCount"] as? Int ?? 0

        // Skip sessions with zero work
        guard linesAdded + linesRemoved > 0 || filesChanged > 0 else { continue }

        let updatedAt = c["lastUpdatedAt"] as? Int64 ?? createdAt

        // Skip sessions older than 7 days
        guard updatedAt >= cutoffMs else { continue }

        let name = c["name"] as? String ?? ""

        var repoPath: String?
        var gitBranch: String?
        if let repos = c["trackedGitRepos"] as? [[String: Any]], let first = repos.first {
            repoPath = first["repoPath"] as? String
        }
        gitBranch = c["committedToBranch"] as? String

        rows.append(CursorComposerRow(
            composerId: cid,
            name: name,
            createdAtMs: createdAt,
            updatedAtMs: updatedAt,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            filesChanged: filesChanged,
            repoPath: repoPath,
            gitBranch: gitBranch,
            mode: mode
        ))
    }

    return rows.sorted { $0.updatedAtMs > $1.updatedAtMs }
}

public func findLatestCursorSession() -> CursorComposerRow? {
    findAllCursorSessions().first
}

// MARK: - Full session parse

/// Maximum inactivity gap before splitting into separate work sessions
private let cursorMaxGapSeconds: TimeInterval = 4 * 3600 // 4 hours

public func parseCursorSession(_ row: CursorComposerRow) -> ParsedSession {
    return parseCursorSessions(row).last ?? makeSingleCursorSession(row)
}

/// Parses a Cursor session, splitting into multiple sessions at 4-hour inactivity gaps.
public func parseCursorSessions(_ row: CursorComposerRow) -> [ParsedSession] {
    // Try to get bubble timestamps for this composer session
    let bubbleTimestamps = getCursorBubbleTimestamps(composerId: row.composerId)

    if bubbleTimestamps.count >= 2 {
        var splitIndices: [Int] = [0]
        for i in 1..<bubbleTimestamps.count {
            let gap = bubbleTimestamps[i].timeIntervalSince(bubbleTimestamps[i-1])
            if gap > cursorMaxGapSeconds {
                splitIndices.append(i)
            }
        }

        if splitIndices.count > 1 {
            let totalSpan = bubbleTimestamps.last!.timeIntervalSince(bubbleTimestamps.first!)
            let repoAlias = row.repoPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            var results: [ParsedSession] = []

            for (segIdx, startIdx) in splitIndices.enumerated() {
                let endIdx = segIdx + 1 < splitIndices.count ? splitIndices[segIdx + 1] : bubbleTimestamps.count
                let segStart = bubbleTimestamps[startIdx]
                let segEnd = bubbleTimestamps[endIdx - 1]
                let segSpan = segEnd.timeIntervalSince(segStart)
                let proportion = totalSpan > 0 ? segSpan / totalSpan : 1.0 / Double(splitIndices.count)

                results.append(ParsedSession(
                    id: "\(row.composerId)_seg\(segIdx)",
                    startedAt: segStart,
                    endedAt: segEnd,
                    activeDuration: segSpan,
                    linesAdded: Int(Double(row.linesAdded) * proportion),
                    linesRemoved: Int(Double(row.linesRemoved) * proportion),
                    filesTouched: row.filesChanged,
                    tokens: 0,
                    model: "cursor",
                    repoAlias: repoAlias,
                    gitBranch: row.gitBranch,
                    source: .cursor
                ))
            }
            return results
        }
    }

    return [makeSingleCursorSession(row)]
}

private func makeSingleCursorSession(_ row: CursorComposerRow) -> ParsedSession {
    let startedAt = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
    let endedAt   = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000.0)
    let repoAlias = row.repoPath.map { URL(fileURLWithPath: $0).lastPathComponent }

    return ParsedSession(
        id: row.composerId,
        startedAt: startedAt,
        endedAt: endedAt,
        activeDuration: endedAt.timeIntervalSince(startedAt),
        linesAdded: row.linesAdded,
        linesRemoved: row.linesRemoved,
        filesTouched: row.filesChanged,
        tokens: 0,
        model: "cursor",
        repoAlias: repoAlias,
        gitBranch: row.gitBranch,
        source: .cursor
    )
}

/// Reads bubble timestamps for a given composer session from cursorDiskKV
private func getCursorBubbleTimestamps(composerId: String) -> [Date] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(cursorDBPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
        return []
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 5000)

    let sql = "SELECT value FROM cursorDiskKV WHERE key LIKE 'bubbleId:\(composerId):%' LIMIT 500"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(stmt) }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var timestamps: [Date] = []

    while sqlite3_step(stmt) == SQLITE_ROW {
        guard let blob = sqlite3_column_text(stmt, 0) else { continue }
        let jsonStr = String(cString: blob)
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let createdAt = obj["createdAt"] as? String,
              let date = isoFormatter.date(from: createdAt)
        else { continue }
        timestamps.append(date)
    }

    return timestamps.sorted()
}
