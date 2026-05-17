import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import DevKatParser

let cliVersion = "DEVKAT_CLI_VERSION_PLACEHOLDER"

let args = CommandLine.arguments
let home = FileManager.default.homeDirectoryForCurrentUser
let claudeDir = home.appendingPathComponent(".claude")
let codexDir  = home.appendingPathComponent(".codex")
let piDir    = home.appendingPathComponent(".pi")

func run() {
    if args.contains("--login")     { return runLogin() }
    if args.contains("--logout")    { return runLogout() }
    if args.contains("--list")      { return listSessions() }
    if args.contains("--install")   { return installDaemon() }
    if args.contains("--uninstall") { return uninstallDaemon() }
    if args.contains("--status")    { return daemonStatus() }
    if args.contains("--sync-all")  { return syncAll(verbose: !args.contains("--quiet")) }
    if args.contains("--cursor-test") { return runCursorTest() }

    // --session <path>  forces a specific session file (auto-detects source)
    if let idx = args.firstIndex(of: "--session"), args.count > idx + 1 {
        let url = URL(fileURLWithPath: args[idx + 1])
        if url.path.contains(".pi/") {
            do {
                let session = try parsePiSession(url)
                try writeSession(session)
                printSummary(session)
            } catch {
                print("devkat-push: error – \(error.localizedDescription)")
                exit(1)
            }
        } else {
            pushClaudeSession(at: url)
        }
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
    case "cursor":
        pushLatestCursorSession()
    case "pi":
        pushLatestPiSession()
    default:
        pushNewestSessionAcrossAllSources()
    }
}

// MARK: - Auto-detect

func pushNewestSessionAcrossAllSources() {
    guard let newest = newestParsedSessionAcrossAllSources() else {
        print("devkat-push: no sessions found in ~/.claude, ~/.codex, Cursor, or ~/.pi")
        exit(1)
    }

    print("devkat-push: auto-detected newest session from \(newest.label)")
    pushParsedSession(newest.session)
}

private func newestParsedSessionAcrossAllSources() -> (label: String, session: ParsedSession)? {
    struct Candidate {
        let date: Date
        let parse: () throws -> ParsedSession
        let label: String
    }

    var candidates: [Candidate] = []

    // Claude
    if let url = findLatestSessionFile(in: claudeDir) {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        candidates.append(Candidate(date: date, parse: { try parseSession(at: url) }, label: "claude"))
    }

    // Codex
    if let row = findLatestCodexSession(in: codexDir) {
        let date = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000.0)
        candidates.append(Candidate(date: date, parse: { parseCodexSession(row) }, label: "codex"))
    }

    // Cursor
    if let row = findLatestCursorSession() {
        let date = Date(timeIntervalSince1970: Double(row.updatedAtMs) / 1000.0)
        candidates.append(Candidate(date: date, parse: { parseCursorSession(row) }, label: "cursor"))
    }

    // Pi
    if let url = findLatestPiSessionFile() {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        candidates.append(Candidate(date: date, parse: { try parsePiSession(url) }, label: "pi"))
    }

    for candidate in candidates.sorted(by: { $0.date > $1.date }) {
        do {
            return (candidate.label, try candidate.parse())
        } catch {
            print("devkat-push: skipped latest \(candidate.label) session – \(error.localizedDescription)")
        }
    }

    return nil
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

func pushLatestCursorSession() {
    guard let row = findLatestCursorSession() else {
        print("devkat-push: no Cursor sessions found")
        exit(1)
    }
    let session = parseCursorSession(row)
    pushParsedSession(session)
}

func pushLatestPiSession() {
    guard let url = findLatestPiSessionFile() else {
        print("devkat-push: no Pi sessions found in ~/.pi/agent/sessions/")
        exit(1)
    }
    print("devkat-push: parsing \(url.lastPathComponent) …")
    do {
        let session = try parsePiSession(url)
        try writeSession(session)
        printSummary(session)
    } catch {
        print("devkat-push: error – \(error.localizedDescription)")
        exit(1)
    }
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
    print("devkat-push: DEVKAT login")
    print("  (no account yet? enter 'signup' as the password to create one)")
    print()

    print("Email: ", terminator: "")
    guard let email = readLine()?.trimmingCharacters(in: .whitespaces), !email.isEmpty else {
        print("devkat-push: cancelled"); exit(1)
    }

    guard let raw = getpass("Password: ") else {
        print("\ndevkat-push: cancelled"); exit(1)
    }
    let password = String(cString: raw).trimmingCharacters(in: .whitespaces)
    guard !password.isEmpty else {
        print("devkat-push: cancelled"); exit(1)
    }

    do {
        let creds: StoredCredentials
        if password == "signup" {
            print("Creating account…")
            var newPassword = ""
            while newPassword.count < 8 {
                guard let pwRaw = getpass("Choose a password (min 8 chars): ") else { break }
                newPassword = String(cString: pwRaw).trimmingCharacters(in: .whitespaces)
            }
            creds = try signUp(email: email, password: newPassword)
            print("devkat-push: ✓ account created and logged in as \(email)")
        } else {
            creds = try signIn(email: email, password: password)
            print("devkat-push: ✓ logged in as \(email)")
        }
        try saveCredentials(creds)
        installDaemon()
    } catch {
        print("devkat-push: login failed – \(error.localizedDescription)")
        exit(1)
    }
}

func runLogout() {
    clearCredentials()
    clearAccountCreatedAt()
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

    let cursorRows = findAllCursorSessions()
        .map { (date: Date(timeIntervalSince1970: Double($0.updatedAtMs) / 1000.0),
                label: "cursor",
                name: "\($0.composerId.prefix(8))… \($0.repoPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?")  \($0.name)") }

    let piFiles = findAllPiSessions()
        .map { (date: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast,
               label: "pi",
               name: $0.lastPathComponent) }

    let all = (claudeFiles + codexRows + cursorRows + piFiles).sorted { $0.date > $1.date }

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
