import Foundation
import DevKatParser

let args = CommandLine.arguments
let home = FileManager.default.homeDirectoryForCurrentUser
let claudeDir = home.appendingPathComponent(".claude")
let codexDir  = home.appendingPathComponent(".codex")

func run() {
    if args.contains("--login")     { return runLogin() }
    if args.contains("--logout")    { return runLogout() }
    if args.contains("--list")      { return listSessions() }
    if args.contains("--install")   { return installDaemon() }
    if args.contains("--uninstall") { return uninstallDaemon() }
    if args.contains("--status")    { return daemonStatus() }
    if args.contains("--sync-all")  { return syncAll(verbose: !args.contains("--quiet")) }

    // --session <path>  forces a specific Claude JSONL file
    if let idx = args.firstIndex(of: "--session"), args.count > idx + 1 {
        let url = URL(fileURLWithPath: args[idx + 1])
        pushClaudeSession(at: url)
        return
    }

    // --source claude|codex  forces a specific tool; otherwise auto-detect newest across all
    let forcedSource = args.firstIndex(of: "--source").flatMap {
        args.count > $0 + 1 ? args[$0 + 1] : nil
    }

    switch forcedSource {
    case "codex":
        pushLatestCodexSession()
    case "claude":
        pushLatestClaudeSession()
    default:
        pushNewestSessionAcrossAllSources()
    }
}

// MARK: - Auto-detect

func pushNewestSessionAcrossAllSources() {
    struct Candidate {
        let date: Date
        let action: () -> Void
        let label: String
    }

    var candidates: [Candidate] = []

    // Claude
    if let url = findLatestSessionFile(in: claudeDir) {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        candidates.append(Candidate(date: date, action: { pushClaudeSession(at: url) }, label: "claude"))
    }

    // Codex
    if let row = findLatestCodexSession(in: codexDir) {
        let date = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000.0)
        candidates.append(Candidate(date: date, action: { pushParsedSession(parseCodexSession(row)) }, label: "codex"))
    }

    guard let newest = candidates.max(by: { $0.date < $1.date }) else {
        print("devkat-push: no sessions found in ~/.claude or ~/.codex")
        exit(1)
    }

    print("devkat-push: auto-detected newest session from \(newest.label)")
    newest.action()
}

// MARK: - Per-source push helpers

func pushLatestClaudeSession() {
    guard let url = findLatestSessionFile(in: claudeDir) else {
        print("devkat-push: no Claude Code sessions found in ~/.claude/projects/")
        exit(1)
    }
    pushClaudeSession(at: url)
}

func pushClaudeSession(at url: URL) {
    print("devkat-push: parsing \(url.lastPathComponent) …")
    do {
        let session = try parseSession(at: url)
        try writeSession(session)
        printSummary(session)
    } catch {
        print("devkat-push: error – \(error.localizedDescription)")
        exit(1)
    }
}

func pushLatestCodexSession() {
    guard let row = findLatestCodexSession(in: codexDir) else {
        print("devkat-push: no Codex sessions found in ~/.codex/state_5.sqlite")
        exit(1)
    }
    let session = parseCodexSession(row)
    pushParsedSession(session)
}

func pushParsedSession(_ session: ParsedSession) {
    do {
        try writeSession(session)
        printSummary(session)
    } catch {
        print("devkat-push: error – \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Login

func runLogin() {
    print("devkat-push: Supabase login")
    print("  (no account yet? enter 'signup' as the password to create one)")
    print()

    print("Email: ", terminator: "")
    guard let email = readLine()?.trimmingCharacters(in: .whitespaces), !email.isEmpty else {
        print("devkat-push: cancelled"); exit(1)
    }

    print("Password: ", terminator: "")
    guard let password = readLine()?.trimmingCharacters(in: .whitespaces), !password.isEmpty else {
        print("devkat-push: cancelled"); exit(1)
    }

    do {
        let creds: StoredCredentials
        if password == "signup" {
            print("Creating account…")
            var newPassword = ""
            while newPassword.count < 8 {
                print("Choose a password (min 8 chars): ", terminator: "")
                newPassword = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            }
            creds = try signUp(email: email, password: newPassword)
            print("devkat-push: ✓ account created and logged in as \(email)")
        } else {
            creds = try signIn(email: email, password: password)
            print("devkat-push: ✓ logged in as \(email)")
        }
        try saveCredentials(creds)
    } catch {
        print("devkat-push: login failed – \(error.localizedDescription)")
        exit(1)
    }
}

func runLogout() {
    clearCredentials()
    print("devkat-push: logged out")
}

// MARK: - List

func listSessions() {
    let claudeFiles = findAllSessionFiles(in: claudeDir)
        .map { (date: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast, label: "claude", name: $0.lastPathComponent) }

    let codexRows = findAllCodexSessions(in: codexDir)
        .map { (date: Date(timeIntervalSince1970: Double($0.updatedAtMs) / 1000.0),
                label: "codex",
                name: "\($0.id.prefix(8))… \($0.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?")") }

    let all = (claudeFiles + codexRows).sorted { $0.date > $1.date }

    if all.isEmpty { print("No session files found."); return }
    print("\(all.count) sessions (newest first):")
    for (i, s) in all.prefix(20).enumerated() {
        let dateStr = DateFormatter.localizedString(from: s.date, dateStyle: .short, timeStyle: .short)
        print("  \(i + 1). [\(s.label)]  \(s.name)  [\(dateStr)]")
    }
}

// MARK: - Helpers

func printSummary(_ s: ParsedSession) {
    let df = DateFormatter(); df.dateFormat = "HH:mm"
    let dur = formatDuration(s.activeDuration)
    print("  ✓ [\(s.source.rawValue)]  \(s.repoAlias ?? "unknown")  \(df.string(from: s.startedAt))–\(df.string(from: s.endedAt))  \(dur)  +\(s.linesAdded)/-\(s.linesRemoved)  \(formatTokens(s.tokens)) tokens  [\(s.model)]")
}

func formatDuration(_ t: TimeInterval) -> String {
    let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60
    return h == 0 ? "\(m)m" : "\(h)h\(String(format: "%02d", m))m"
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

run()
