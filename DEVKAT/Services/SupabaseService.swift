import Foundation

struct AuthTokens {
    let accessToken: String
    let refreshToken: String

    static var stored: AuthTokens? {
        guard let access = Keychain.load(key: "access_token"),
              let refresh = Keychain.load(key: "refresh_token") else { return nil }
        return AuthTokens(accessToken: access, refreshToken: refresh)
    }

    func persist() {
        Keychain.save(accessToken,  key: "access_token")
        Keychain.save(refreshToken, key: "refresh_token")
    }

    static func clear() {
        Keychain.delete(key: "access_token")
        Keychain.delete(key: "refresh_token")
    }
}

// MARK: - Supabase REST + Auth service

actor SupabaseService {
    static let shared = SupabaseService()

    private let base = URL(string: Config.supabaseURL)!
    private let anon = Config.supabaseAnonKey

    // MARK: Auth

    func signIn(email: String, password: String) async throws -> AuthTokens {
        try await authRequest(
            url: base.appendingPathComponent("auth/v1/token").appending(queryItems: [.init(name: "grant_type", value: "password")]),
            body: ["email": email, "password": password]
        )
    }

    func signUp(email: String, password: String) async throws -> AuthTokens {
        try await authRequest(
            url: base.appendingPathComponent("auth/v1/signup"),
            body: ["email": email, "password": password]
        )
    }

    func refreshTokens(_ refresh: String) async throws -> AuthTokens {
        try await authRequest(
            url: base.appendingPathComponent("auth/v1/token").appending(queryItems: [.init(name: "grant_type", value: "refresh_token")]),
            body: ["refresh_token": refresh]
        )
    }

    private func authRequest(url: URL, body: [String: String]) async throws -> AuthTokens {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            print("SupabaseService auth → HTTP \(http.statusCode)")
            if !(200...299).contains(http.statusCode) {
                print("SupabaseService auth error body → \(String(data: data, encoding: .utf8) ?? "<binary>")")
            }
        }
        try checkStatus(response, data: data)

        struct AuthResp: Decodable {
            let access_token: String
            let refresh_token: String
        }
        let resp = try JSONDecoder().decode(AuthResp.self, from: data)
        return AuthTokens(accessToken: resp.access_token, refreshToken: resp.refresh_token)
    }

    // MARK: Sessions

    func fetchSessions(token: String) async throws -> [Session] {
        var comps = URLComponents(url: base.appendingPathComponent("rest/v1/sessions"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "select", value: "*"),
            .init(name: "order",  value: "started_at.desc"),
            .init(name: "limit",  value: "200"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue(anon,              forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let str = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: str) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: str) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date: \(str)"))
        }
        return try decoder.decode([Session].self, from: data)
    }

    func deleteCurrentUser(token: String) async throws {
        let url = base.appendingPathComponent("rest/v1/rpc/delete_current_user")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        try checkStatus(response, data: data)
    }

    // MARK: Helpers

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            // Surface a human-readable message when Supabase returns one
            struct SupabaseErrorBody: Decodable {
                let message: String?
                let error_description: String?
                let msg: String?
            }
            if let parsed = try? JSONDecoder().decode(SupabaseErrorBody.self, from: data),
               let msg = parsed.message ?? parsed.error_description ?? parsed.msg {
                throw SupabaseError.http(http.statusCode, msg)
            }
            throw SupabaseError.http(http.statusCode, body)
        }
    }
}

enum SupabaseError: LocalizedError {
    case http(Int, String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .http(_, let body) where body.contains("email_not_confirmed"):
            return "Check your inbox — you need to confirm your email before signing in."
        case .http(_, let body) where body.contains("Invalid login credentials"):
            return "Wrong email or password."
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .notLoggedIn: return "Not logged in"
        }
    }
}
