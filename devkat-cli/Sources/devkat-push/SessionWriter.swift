import Foundation
import DevKatParser

// RPC params for merge_session — snake_case to match Postgres function args.
// Custom encode to always include null keys (PostgREST requires all params present).
private struct MergeParams: Encodable {
    let p_id: String
    let p_started_at: String
    let p_ended_at: String
    let p_active_duration: Double
    let p_lines_added: Int
    let p_lines_removed: Int
    let p_files_touched: Int
    let p_tokens: Int
    let p_model: String
    let p_repo_alias: String?
    let p_git_branch: String?
    let p_source: String

    enum CodingKeys: String, CodingKey {
        case p_id, p_started_at, p_ended_at, p_active_duration
        case p_lines_added, p_lines_removed, p_files_touched
        case p_tokens, p_model, p_repo_alias, p_git_branch, p_source
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_id, forKey: .p_id)
        try c.encode(p_started_at, forKey: .p_started_at)
        try c.encode(p_ended_at, forKey: .p_ended_at)
        try c.encode(p_active_duration, forKey: .p_active_duration)
        try c.encode(p_lines_added, forKey: .p_lines_added)
        try c.encode(p_lines_removed, forKey: .p_lines_removed)
        try c.encode(p_files_touched, forKey: .p_files_touched)
        try c.encode(p_tokens, forKey: .p_tokens)
        try c.encode(p_model, forKey: .p_model)
        try c.encodeIfPresent(p_repo_alias, forKey: .p_repo_alias)
        if p_repo_alias == nil { try c.encodeNil(forKey: .p_repo_alias) }
        try c.encodeIfPresent(p_git_branch, forKey: .p_git_branch)
        if p_git_branch == nil { try c.encodeNil(forKey: .p_git_branch) }
        try c.encode(p_source, forKey: .p_source)
    }
}

public func writeSession(_ session: ParsedSession) throws {
    let token = try validAccessToken()

    let fmt = ISO8601DateFormatter()
    let params = MergeParams(
        p_id: session.id,
        p_started_at: fmt.string(from: session.startedAt),
        p_ended_at: fmt.string(from: session.endedAt),
        p_active_duration: session.activeDuration,
        p_lines_added: session.linesAdded,
        p_lines_removed: session.linesRemoved,
        p_files_touched: session.filesTouched,
        p_tokens: session.tokens,
        p_model: session.model,
        p_repo_alias: session.repoAlias,
        p_git_branch: session.gitBranch,
        p_source: session.source.rawValue
    )

    let url = URL(string: "\(supabaseURL)/rest/v1/rpc/merge_session")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let encoder = JSONEncoder()
    req.httpBody = try encoder.encode(params)

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
    print("devkat-push: → synced (\(session.source.rawValue) · \(session.id.prefix(8))…)")
}
