import Foundation

// MARK: - Pi.dev session discovery

/// Reads sessions from ~/.pi/agent/sessions/.
/// Pi stores sessions as JSONL files under:
///   ~/.pi/agent/sessions/--<path>--/<timestamp>_<uuid>.jsonl

private let piSessionsDir: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".pi").appendingPathComponent("agent").appendingPathComponent("sessions")
}()

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

// MARK: - JSONL Parsing (usage-only)

/// Minimal JSONL record — only captures metadata needed for session stats.
private struct PiRecord: Decodable {
    let type: String
    let timestamp: String?
    let cwd: String?
    let message: PiMessage?
    let modelId: String?
}

/// Minimal message — only captures usage and model metadata.
private struct PiMessage: Decodable {
    let role: String?
    let model: String?
    let usage: PiUsage?
}

/// Usage from Pi.dev assistant messages.
private struct PiUsage: Decodable {
    let totalTokens: Int
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

    struct TimedRecord {
        let timestamp: Date
        let record: PiRecord
    }

    var timedRecords: [TimedRecord] = []
    var cwd: String?
    var model = "llamacpp"
    var totalTokens = 0

    for line in lines {
        guard let record = try? decoder.decode(PiRecord.self, from: Data(line)) else { continue }

        // Session header — extract cwd
        if record.type == "session", let c = record.cwd {
            cwd = c
        }

        // Model change — update model
        if record.type == "model_change", let m = record.modelId {
            model = m
        }

        // Message — extract usage from assistant messages
        if record.type == "message", let msg = record.message {
            if let tsStr = record.timestamp, let date = isoFormatter.date(from: tsStr) {
                timedRecords.append(TimedRecord(timestamp: date, record: record))
            }

            // Accumulate tokens from all assistant messages
            if msg.role == "assistant", let usage = msg.usage {
                totalTokens += usage.totalTokens
            }

            // Track model from first assistant message
            if msg.role == "assistant", let m = msg.model, model == "llamacpp" {
                model = m
            }
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
    let sessionBase = url.deletingPathExtension().lastPathComponent
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
            linesAdded: 0,
            linesRemoved: 0,
            filesTouched: 0,
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
