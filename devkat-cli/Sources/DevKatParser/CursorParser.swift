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

public func findAllCursorSessions() -> [CursorComposerRow] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(cursorDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        return []
    }
    defer { sqlite3_close(db) }

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

public func parseCursorSession(_ row: CursorComposerRow) -> ParsedSession {
    let startedAt = Date(timeIntervalSince1970: Double(row.createdAtMs) / 1000.0)
    let endedAt   = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000.0)
    let activeDuration = endedAt.timeIntervalSince(startedAt)

    let repoAlias = row.repoPath.map { URL(fileURLWithPath: $0).lastPathComponent }

    return ParsedSession(
        id: row.composerId,
        startedAt: startedAt,
        endedAt: endedAt,
        activeDuration: activeDuration,
        linesAdded: row.linesAdded,
        linesRemoved: row.linesRemoved,
        filesTouched: row.filesChanged,
        tokens: 0,  // Cursor doesn't expose per-session token counts
        model: "cursor",
        repoAlias: repoAlias,
        gitBranch: row.gitBranch,
        source: .cursor
    )
}
