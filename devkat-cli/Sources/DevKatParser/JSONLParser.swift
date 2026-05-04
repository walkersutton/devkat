import Foundation

// MARK: - Public output type

public enum SessionSource: String, Codable {
    case claude
    case codex
    case cursor
}

public struct ParsedSession: Codable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let activeDuration: TimeInterval
    public let linesAdded: Int
    public let linesRemoved: Int
    public let filesTouched: Int
    public let tokens: Int
    public let model: String
    public let repoAlias: String?
    public let gitBranch: String?
    public let source: SessionSource

    public init(
        id: String, startedAt: Date, endedAt: Date,
        activeDuration: TimeInterval, linesAdded: Int, linesRemoved: Int,
        filesTouched: Int, tokens: Int, model: String,
        repoAlias: String?, gitBranch: String?,
        source: SessionSource = .claude
    ) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt
        self.activeDuration = activeDuration; self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved; self.filesTouched = filesTouched
        self.tokens = tokens; self.model = model
        self.repoAlias = repoAlias; self.gitBranch = gitBranch
        self.source = source
    }
}

// MARK: - JSONL record types

private struct JSONLRecord: Decodable {
    let type: String
    let subtype: String?
    let timestamp: String?
    let requestId: String?
    let durationMs: Int?
    let message: JSONLMessage?
    let toolUseResult: JSONLToolUseResult?
    let cwd: String?
    let gitBranch: String?
}

private struct JSONLMessage: Decodable {
    let role: String?
    let model: String?
    let usage: JSONLUsage?
    let content: JSONLContent?
}

private enum JSONLContent: Decodable {
    case text(String)
    case blocks([JSONLContentBlock])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .text(s)
        } else {
            self = .blocks((try? c.decode([JSONLContentBlock].self)) ?? [])
        }
    }
}

private struct JSONLContentBlock: Decodable {
    let type: String
    let name: String?
}

private struct JSONLUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

private struct JSONLToolUseResult: Decodable {
    let filePath: String?
    let structuredPatch: [JSONLPatchHunk]?
    let type: String?
}

private struct JSONLPatchHunk: Decodable {
    let lines: [String]
}

// MARK: - Parser

public enum JSONLParseError: Error {
    case emptyFile
    case couldNotReadFile(URL)
}

public func parseSession(at url: URL) throws -> ParsedSession {
    guard let data = try? Data(contentsOf: url) else {
        throw JSONLParseError.couldNotReadFile(url)
    }

    let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
    guard !lines.isEmpty else { throw JSONLParseError.emptyFile }

    let decoder = JSONDecoder()
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var timestamps: [Date] = []
    var activeDurationMs: Int = 0
    var linesAdded = 0
    var linesRemoved = 0
    var touchedFiles = Set<String>()
    var seenRequestIds = Set<String>()
    var totalTokens = 0
    var model = "claude"
    var cwd: String?
    var gitBranch: String?

    for line in lines {
        guard let record = try? decoder.decode(JSONLRecord.self, from: Data(line)) else { continue }

        // Timestamps
        if let tsStr = record.timestamp,
           let date = isoFormatter.date(from: tsStr) {
            timestamps.append(date)
        }

        // cwd and gitBranch from user records
        if record.type == "user" {
            if cwd == nil, let c = record.cwd { cwd = c }
            if gitBranch == nil, let b = record.gitBranch { gitBranch = b }
        }

        // Active duration from turn_duration system events
        if record.type == "system",
           record.subtype == "turn_duration",
           let ms = record.durationMs {
            activeDurationMs += ms
        }

        // Tokens -- deduplicate by requestId
        if record.type == "assistant",
           let msg = record.message,
           msg.model != "<synthetic>",
           let usage = msg.usage {
            let rid = record.requestId ?? UUID().uuidString
            if !seenRequestIds.contains(rid) {
                seenRequestIds.insert(rid)
                totalTokens += (usage.inputTokens ?? 0)
                    + (usage.outputTokens ?? 0)
                    + (usage.cacheReadInputTokens ?? 0)
                    + (usage.cacheCreationInputTokens ?? 0)
                if let m = msg.model, m != "<synthetic>", model == "claude" {
                    model = m
                }
            }
        }

        // Lines added/removed from structuredPatch
        if let result = record.toolUseResult {
            if let patches = result.structuredPatch {
                for hunk in patches {
                    for patchLine in hunk.lines {
                        if patchLine.hasPrefix("+") { linesAdded += 1 }
                        else if patchLine.hasPrefix("-") { linesRemoved += 1 }
                    }
                }
            }
            if let fp = result.filePath {
                touchedFiles.insert(fp)
            }
        }
    }

    let startedAt = timestamps.min() ?? Date()
    let endedAt   = timestamps.max() ?? Date()
    let activeDuration: TimeInterval = activeDurationMs > 0
        ? TimeInterval(activeDurationMs) / 1000.0
        : endedAt.timeIntervalSince(startedAt)

    let repoAlias = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
    let sessionId = url.deletingPathExtension().lastPathComponent

    return ParsedSession(
        id: sessionId,
        startedAt: startedAt,
        endedAt: endedAt,
        activeDuration: activeDuration,
        linesAdded: linesAdded,
        linesRemoved: linesRemoved,
        filesTouched: touchedFiles.count,
        tokens: totalTokens,
        model: model,
        repoAlias: repoAlias,
        gitBranch: gitBranch,
        source: .claude
    )
}

// MARK: - Session discovery

public func findAllSessionFiles(in claudeDir: URL) -> [URL] {
    let fm = FileManager.default
    guard let projectDirs = try? fm.contentsOfDirectory(
        at: claudeDir.appendingPathComponent("projects"),
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles
    ) else { return [] }

    var results: [URL] = []
    for projectDir in projectDirs {
        guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { continue }

        guard let files = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { continue }

        // Only top-level .jsonl files (skip subagents/ subdirectory)
        for file in files where file.pathExtension == "jsonl" {
            results.append(file)
        }
    }
    return results
}

public func findLatestSessionFile(in claudeDir: URL) -> URL? {
    findAllSessionFiles(in: claudeDir)
        .max {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return a < b
        }
}
