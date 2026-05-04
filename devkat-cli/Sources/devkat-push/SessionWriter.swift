import Foundation
import DevKatParser

// Supabase row -- snake_case to match the database columns
private struct SessionRow: Encodable {
    let id: String
    let startedAt: String
    let endedAt: String
    let activeDuration: Double
    let linesAdded: Int
    let linesRemoved: Int
    let filesTouched: Int
    let tokens: Int
    let model: String
    let repoAlias: String?
    let gitBranch: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt    = "started_at"
        case endedAt      = "ended_at"
        case activeDuration = "active_duration"
        case linesAdded   = "lines_added"
        case linesRemoved = "lines_removed"
        case filesTouched = "files_touched"
        case tokens
        case model
        case repoAlias    = "repo_alias"
        case gitBranch    = "git_branch"
        case source
    }
}

public func writeSession(_ session: ParsedSession) throws {
    let token = try validAccessToken()

    let fmt = ISO8601DateFormatter()
    let row = SessionRow(
        id: session.id,
        startedAt: fmt.string(from: session.startedAt),
        endedAt: fmt.string(from: session.endedAt),
        activeDuration: session.activeDuration,
        linesAdded: session.linesAdded,
        linesRemoved: session.linesRemoved,
        filesTouched: session.filesTouched,
        tokens: session.tokens,
        model: session.model,
        repoAlias: session.repoAlias,
        gitBranch: session.gitBranch,
        source: session.source.rawValue
    )

    let url = URL(string: "\(supabaseURL)/rest/v1/sessions")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

    let encoder = JSONEncoder()
    req.httpBody = try encoder.encode(row)

    let sem = DispatchSemaphore(value: 0)
    var writeError: Error?

    URLSession.shared.dataTask(with: req) { data, response, error in
        defer { sem.signal() }
        if let error { writeError = error; return }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            writeError = AuthError(message: "HTTP \(http.statusCode): \(body)")
        }
    }.resume()

    sem.wait()

    if let writeError { throw writeError }
    print("devkat-push: → synced to Supabase (\(session.source.rawValue) · \(session.id.prefix(8))…)")
}
