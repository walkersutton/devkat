import Foundation

// MARK: - Pi.dev session discovery

/// Reads sessions from ~/.pi/agent/sessions/.
/// Pi stores sessions as JSONL files under:
///   ~/.pi/agent/sessions/--<path>--/<timestamp>_<uuid>.jsonl

private let piSessionsDir: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".pi").appendingPathComponent("agent").appendingPathComponent("sessions")
}()

public struct PiSessionRow {
    public let sessionId: String
    public let path: String
    public let createdAt: Date
    public let updatedAt: Date
    public let cwd: String?
    public let model: String
    public let provider: String
    public let totalTokens: Int
    public let totalLinesAdded: Int
    public let totalLinesRemoved: Int
    public let filesTouched: Set<String>
}

/// Finds all Pi.dev session files modified since the cutoff.
public func findAllPiSessions(since cutoff: Date = Date(timeIntervalSince1970: 0)) -> [URL] {
    let fm = FileManager.default
    guard let sessionDirs = try? fm.contentsOfDirectory(
        at: piSessionsDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    ) else { return [] }

    var results: [URL] = []
    for projectDir in sessionDirs {
        guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { continue }

        guard let files = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { continue }

        for file in files where file.pathExtension == "jsonl" {
            let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mod >= cutoff { results.append(file) }
        }
    }
    return results
}

/// Finds the latest Pi.dev session file.
public func findLatestPiSessionFile() -> URL? {
    findAllPiSessions()
        .max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a < b
        }
}

// MARK: - JSONL Parsing

private struct PiRecord: Decodable {
    let type: String
    let id: String?
    let parentId: String?
    let timestamp: String?
    let version: Int?
    let cwd: String?
    let message: PiMessage?
    let provider: String?
    let modelId: String?
    let thinkingLevel: String?
    let summary: String?
    let tokensBefore: Int?
    let firstKeptEntryId: String?
    let fromId: String?
}

private struct PiMessage: Decodable {
    let role: String?
    let content: PiContent?
    let provider: String?
    let model: String?
    let usage: PiUsage?
    let stopReason: String?
    let timestamp: Int64?
    let toolCallId: String?
    let toolName: String?
    let isError: Bool?
    let command: String?
    let output: String?
    let exitCode: Int?
    let customType: String?
    let fromHook: Bool?
}

private enum PiContent: Decodable {
    case text(String)
    case blocks([PiContentBlock])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .text(s)
        } else {
            self = .blocks((try? c.decode([PiContentBlock].self)) ?? [])
        }
    }
}

private struct PiContentBlock: Decodable {
    let type: String
    let text: String?
    let thinking: String?
    let id: String?
    let name: String?
    let arguments: String?
    let data: String?
    let mimeType: String?
}

private struct PiUsage: Decodable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case input, output, cacheRead, cacheWrite, totalTokens
    }
}

// MARK: - Session Parsing

/// Maximum inactivity gap before splitting into separate work sessions
private let piMaxGapSeconds: TimeInterval = 4 * 3600 // 4 hours

/// Parses a Pi.dev JSONL session file into a ParsedSession.
public func parsePiSession(_ url: URL) throws -> ParsedSession {
    let sessions = try parsePiSessions(url)
    return sessions.last!
}

/// Parses a Pi.dev JSONL file, splitting into multiple sessions at 4-hour gaps.
public func parsePiSessions(_ url: URL) throws -> [ParsedSession] {
    guard let data = try? Data(contentsOf: url) else {
        throw JSONLParseError.couldNotReadFile(url)
    }

    let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    guard !lines.isEmpty else { throw JSONLParseError.emptyFile }

    let decoder = JSONDecoder()
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    // First pass: collect all records with timestamps
    struct TimedRecord {
        let timestamp: Date
        let record: PiRecord
    }

    var timedRecords: [TimedRecord] = []
    var cwd: String?
    var model = "llamacpp"
    var totalTokens = 0
    var linesAdded = 0
    var linesRemoved = 0
    var touchedFiles = Set<String>()
    var sessionIdBase: String?

    for line in lines {
        guard let record = try? decoder.decode(PiRecord.self, from: Data(line)) else { continue }

        // Session header
        if record.type == "session", let ver = record.version {
            if ver >= 2 {
                sessionIdBase = record.id
            }
            if let c = record.cwd { cwd = c }
        }

        // Model change
        if record.type == "model_change" {
            if let m = record.modelId { model = m }
        }

        // Message
        if record.type == "message", let msg = record.message {
            if let tsStr = record.timestamp, let date = isoFormatter.date(from: tsStr) {
                timedRecords.append(TimedRecord(timestamp: date, record: record))
            }

            if let usage = msg.usage {
                totalTokens += usage.totalTokens
            }

            // Track model from first assistant message
            if msg.role == "assistant", let m = msg.model, model == "llamacpp" {
                model = m
            }

            // Count diff lines from bash execution output
            if msg.role == "bashExecution", let output = msg.output {
                let isGitDiff = output.contains("diff")
                if isGitDiff {
                    for diffLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
                        let s = String(diffLine)
                        if s.hasPrefix("+") && !s.hasPrefix("+++") { linesAdded += 1 }
                        else if s.hasPrefix("-") && !s.hasPrefix("---") { linesRemoved += 1 }
                        if s.hasPrefix("+++ b/") {
                            touchedFiles.insert(String(s.dropFirst(6)))
                        }
                    }
                }
            }

            // Track files from tool calls (read command)
            if let content = msg.content {
                if case .blocks(let blocks) = content {
                    for block in blocks {
                        if block.type == "toolCall", let args = block.arguments {
                            // Try to extract file path from bash commands
                            if let data = args.data(using: .utf8),
                               let cmd = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let command = cmd["command"] as? String {
                                if command.contains("cat ") || command.contains("read ") {
                                    // Extract file path from command
                                    let parts = command.split(separator: " ")
                                    if parts.count >= 2 {
                                        let path = String(parts[parts.count - 1])
                                        if !path.isEmpty && path != "." {
                                            touchedFiles.insert(path)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Compaction entry (has token count)
        // Compaction doesn't add tokens, just summarizes
        if record.type == "compaction" {
            _ = record.tokensBefore
        }
    }

    guard !timedRecords.isEmpty else { throw JSONLParseError.emptyFile }

    // Sort by timestamp
    timedRecords.sort { $0.timestamp < $1.timestamp }

    // Find split points (gaps > 4 hours)
    var splitIndices: [Int] = [0]
    for i in 1..<timedRecords.count {
        let gap = timedRecords[i].timestamp.timeIntervalSince(timedRecords[i - 1].timestamp)
        if gap > piMaxGapSeconds {
            splitIndices.append(i)
        }
    }

    // Build sessions from each segment
    let sessionBase = sessionIdBase ?? url.deletingPathExtension().lastPathComponent
    var results: [ParsedSession] = []

    for (segIdx, startIdx) in splitIndices.enumerated() {
        let endIdx = segIdx + 1 < splitIndices.count ? splitIndices[segIdx + 1] : timedRecords.count
        let segment = timedRecords[startIdx..<endIdx]

        let segStart = segment.first!.timestamp
        let segEnd = segment.last!.timestamp
        let activeDuration = segEnd.timeIntervalSince(segStart)

        let repoAlias = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let sessionId = splitIndices.count > 1
            ? "\(sessionBase)_seg\(segIdx)"
            : sessionBase

        results.append(ParsedSession(
            id: sessionId,
            startedAt: segStart,
            endedAt: segEnd,
            activeDuration: activeDuration,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            filesTouched: touchedFiles.count,
            tokens: totalTokens,
            model: model,
            repoAlias: repoAlias,
            gitBranch: nil,
            source: .pi
        ))
    }

    return results
}

/// Finds the latest Pi session and returns a ParsedSession.
public func findLatestPiSession() -> ParsedSession? {
    guard let url = findLatestPiSessionFile() else { return nil }
    return try? parsePiSession(url)
}
