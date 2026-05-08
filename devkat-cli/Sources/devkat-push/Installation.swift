import Foundation

// Tells the backend "this Mac has run the installer / is alive". The iOS
// app reads the installations table to switch the empty state from
// "paste this curl command" to "waiting for your first session".
//
// Failures are non-fatal — sync should never break because a heartbeat
// dropped a packet.

private struct UpsertInstallationParams: Encodable {
    let p_hostname: String
    let p_cli_version: String
}

private func currentHostname() -> String {
    let h = Host.current().localizedName?.trimmingCharacters(in: .whitespaces)
    if let h, !h.isEmpty { return h }
    let raw = ProcessInfo.processInfo.hostName
    return raw.isEmpty ? "unknown" : raw
}

@discardableResult
func upsertInstallation() -> Bool {
    let token: String
    do {
        token = try validAccessToken()
    } catch {
        return false
    }

    guard let url = URL(string: "\(supabaseURL)/rest/v1/rpc/upsert_installation") else {
        return false
    }

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let params = UpsertInstallationParams(p_hostname: currentHostname(), p_cli_version: cliVersion)
    do {
        req.httpBody = try JSONEncoder().encode(params)
    } catch {
        return false
    }

    let sem = DispatchSemaphore(value: 0)
    var ok = false

    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    let urlSession = URLSession(configuration: config)

    urlSession.dataTask(with: req) { _, response, _ in
        defer { sem.signal() }
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            ok = true
        }
    }.resume()

    _ = sem.wait(timeout: .now() + 30)
    return ok
}
