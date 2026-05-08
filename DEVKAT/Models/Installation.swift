import Foundation

struct Installation: Identifiable, Hashable, Codable {
    var id: String { hostname }
    let hostname: String
    let installedAt: Date
    let lastSeenAt: Date
    let cliVersion: String?

    enum CodingKeys: String, CodingKey {
        case hostname
        case installedAt = "installed_at"
        case lastSeenAt  = "last_seen_at"
        case cliVersion  = "cli_version"
    }
}
