import Foundation

// Tracks which sessions have already been synced to Supabase.
// Stored at ~/.devkat/synced.json as a simple set of session IDs.

private var syncedURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".devkat/synced.json")
}

struct SyncState {
    private var ids: Set<String>

    static func load() -> SyncState {
        guard let data = try? Data(contentsOf: syncedURL),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return SyncState(ids: []) }
        return SyncState(ids: Set(arr))
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    mutating func mark(_ id: String) {
        ids.insert(id)
    }

    func save() {
        let sorted = ids.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        let dir = syncedURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: syncedURL, options: .atomic)
    }

    var count: Int { ids.count }
}
