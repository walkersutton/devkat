import Foundation

// Supabase project constants -- same for all users of the app
let supabaseURL    = "https://sbuskyzrwhlqlxxkoozq.supabase.co"
let supabaseAnonKey = "sb_publishable_lv4uG0KNeJVXiqg9jekuVg_7fkXUwgK"

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn    = "expires_in"
    }
}

struct AuthError: Codable, Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Stored credentials

struct StoredCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

private var configURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".devkat/config.json")
}

func loadCredentials() -> StoredCredentials? {
    guard let data = try? Data(contentsOf: configURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(StoredCredentials.self, from: data)
}

func saveCredentials(_ creds: StoredCredentials) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(creds)
    let dir = configURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: configURL, options: .atomic)
}

func clearCredentials() {
    try? FileManager.default.removeItem(at: configURL)
}

// MARK: - Install timestamp
// Sessions started before this time are never pushed.
// Written once on --install and never changed.

private var installTimestampURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".devkat/installed_at.txt")
}

func loadInstallTimestamp() -> Date {
    guard let str = try? String(contentsOf: installTimestampURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
          let ts = TimeInterval(str) else {
        return Date() // If missing, default to now (nothing gets synced)
    }
    return Date(timeIntervalSince1970: ts)
}

func writeInstallTimestamp() {
    let ts = String(Date().timeIntervalSince1970)
    let dir = installTimestampURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Only write once — never overwrite
    guard !FileManager.default.fileExists(atPath: installTimestampURL.path) else { return }
    try? ts.write(to: installTimestampURL, atomically: true, encoding: .utf8)
}


func signIn(email: String, password: String) throws -> StoredCredentials {
    let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.httpBody = try JSONEncoder().encode(["email": email, "password": password])

    return try performAuthRequest(req)
}

func signUp(email: String, password: String) throws -> StoredCredentials {
    let url = URL(string: "\(supabaseURL)/auth/v1/signup")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.httpBody = try JSONEncoder().encode(["email": email, "password": password])

    return try performAuthRequest(req)
}

func refreshToken(_ refreshToken: String) throws -> StoredCredentials {
    let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token")!
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

    return try performAuthRequest(req)
}

private func performAuthRequest(_ req: URLRequest) throws -> StoredCredentials {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<StoredCredentials, Error> = .failure(AuthError(message: "No response"))

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    let urlSession = URLSession(configuration: config)

    urlSession.dataTask(with: req) { data, response, error in
        defer { sem.signal() }
        if let error { result = .failure(error); return }
        guard let data else { result = .failure(AuthError(message: "Empty response")); return }

        let decoder = JSONDecoder()
        if let auth = try? decoder.decode(AuthResponse.self, from: data) {
            let creds = StoredCredentials(
                accessToken: auth.accessToken,
                refreshToken: auth.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(auth.expiresIn))
            )
            result = .success(creds)
        } else if let err = try? decoder.decode(AuthError.self, from: data) {
            result = .failure(err)
        } else {
            result = .failure(AuthError(message: String(data: data, encoding: .utf8) ?? "Unknown error"))
        }
    }.resume()

    let waitResult = sem.wait(timeout: .now() + 60)
    if waitResult == .timedOut {
        throw AuthError(message: "Request timed out")
    }
    return try result.get()
}

// MARK: - Get valid token (auto-refresh)

func validAccessToken() throws -> String {
    guard var creds = loadCredentials() else {
        throw AuthError(message: "Not logged in. Run: devkat-push --login")
    }
    if creds.isExpired {
        creds = try refreshToken(creds.refreshToken)
        try saveCredentials(creds)
    }
    return creds.accessToken
}
