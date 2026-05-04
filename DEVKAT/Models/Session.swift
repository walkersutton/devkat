import Foundation

struct Session: Identifiable, Hashable, Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let activeDuration: TimeInterval
    let linesAdded: Int
    let linesRemoved: Int
    let filesTouched: Int
    let tokens: Int
    let model: String
    let repoAlias: String?
    let gitBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt      = "started_at"
        case endedAt        = "ended_at"
        case activeDuration = "active_duration"
        case linesAdded     = "lines_added"
        case linesRemoved   = "lines_removed"
        case filesTouched   = "files_touched"
        case tokens
        case model
        case repoAlias      = "repo_alias"
        case gitBranch      = "git_branch"
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    var linesTotal: Int { linesAdded + linesRemoved }
    var linesPerHour: Int {
        let hours = max(activeDuration / 3600, 0.0001)
        return Int(Double(linesTotal) / hours)
    }
}

// MARK: - Formatting

enum SessionFormatting {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return "\(h)h \(String(format: "%02d", m))m"
    }

    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    static func dayLabel(for date: Date, today: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date).uppercased()
    }
}
