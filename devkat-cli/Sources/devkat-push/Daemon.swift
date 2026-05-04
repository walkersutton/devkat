import Foundation
import DevKatParser

// MARK: - Sync all unsynced sessions across every source

func syncAll(verbose: Bool = false) {
    guard loadCredentials() != nil else {
        print("devkat-push: not logged in. Run: devkat-push --login")
        exit(1)
    }

    var state = SyncState.load()
    var pushed = 0
    var failed = 0

    let home = FileManager.default.homeDirectoryForCurrentUser
    let claudeDir = home.appendingPathComponent(".claude")
    let codexDir  = home.appendingPathComponent(".codex")

    // ── Claude sessions ──
    let claudeFiles = findAllSessionFiles(in: claudeDir)
    for url in claudeFiles {
        let sid = url.deletingPathExtension().lastPathComponent
        guard !state.contains(sid) else { continue }

        do {
            let session = try parseSession(at: url)
            // Skip trivially short sessions (< 60s or 0 tokens)
            guard session.tokens > 0, session.activeDuration >= 60 else {
                state.mark(sid)
                continue
            }
            try writeSession(session)
            state.mark(sid)
            pushed += 1
            if verbose { printSyncLine(session) }
        } catch {
            failed += 1
            if verbose { print("  ✗ claude/\(sid.prefix(8))… \(error.localizedDescription)") }
        }
    }

    // ── Codex sessions ──
    let codexRows = findAllCodexSessions(in: codexDir)
    for row in codexRows {
        guard !state.contains(row.id) else { continue }

        let session = parseCodexSession(row)
        guard session.tokens > 0, session.activeDuration >= 60 else {
            state.mark(row.id)
            continue
        }

        do {
            try writeSession(session)
            state.mark(row.id)
            pushed += 1
            if verbose { printSyncLine(session) }
        } catch {
            failed += 1
            if verbose { print("  ✗ codex/\(row.id.prefix(8))… \(error.localizedDescription)") }
        }
    }

    state.save()

    if pushed == 0 && failed == 0 {
        if verbose { print("devkat-push: everything up to date") }
    } else {
        print("devkat-push: synced \(pushed) session\(pushed == 1 ? "" : "s")\(failed > 0 ? ", \(failed) failed" : "")")
    }
}

private func printSyncLine(_ s: ParsedSession) {
    let df = DateFormatter(); df.dateFormat = "MMM d HH:mm"
    print("  ✓ [\(s.source.rawValue)]  \(s.repoAlias ?? "?")  \(df.string(from: s.startedAt))  \(formatTokens(s.tokens)) tokens")
}

// MARK: - launchd install / uninstall

private let launchLabel = "com.devkat.push"

private var plistURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/LaunchAgents/\(launchLabel).plist")
}

func installDaemon() {
    // Find the devkat-push binary path
    let binaryPath = CommandLine.arguments[0].hasPrefix("/")
        ? CommandLine.arguments[0]
        : FileManager.default.currentDirectoryPath + "/" + CommandLine.arguments[0]

    let resolved = URL(fileURLWithPath: binaryPath).standardizedFileURL.path

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let logPath = "\(home)/.devkat/daemon.log"

    // Run every 5 minutes; also trigger on Codex sqlite changes
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(launchLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(resolved)</string>
            <string>--sync-all</string>
        </array>
        <key>StartInterval</key>
        <integer>300</integer>
        <key>WatchPaths</key>
        <array>
            <string>\(home)/.codex/state_5.sqlite</string>
        </array>
        <key>StandardOutPath</key>
        <string>\(logPath)</string>
        <key>StandardErrorPath</key>
        <string>\(logPath)</string>
        <key>RunAtLoad</key>
        <true/>
    </dict>
    </plist>
    """

    do {
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)

        // Load the agent
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["load", plistURL.path]
        try task.run()
        task.waitUntilExit()

        print("devkat-push: daemon installed")
        print("  binary:   \(resolved)")
        print("  plist:    \(plistURL.path)")
        print("  log:      \(logPath)")
        print("  interval: every 5 min + on Codex activity")
        print()
        print("Sessions will now sync automatically. Check status with: devkat-push --status")
    } catch {
        print("devkat-push: failed to install daemon – \(error.localizedDescription)")
        exit(1)
    }
}

func uninstallDaemon() {
    // Unload first
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    task.arguments = ["unload", plistURL.path]
    try? task.run()
    task.waitUntilExit()

    try? FileManager.default.removeItem(at: plistURL)
    print("devkat-push: daemon uninstalled")
}

func daemonStatus() {
    let plistExists = FileManager.default.fileExists(atPath: plistURL.path)

    if plistExists {
        // Check if loaded
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list", launchLabel]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()

        let running = task.terminationStatus == 0
        print("devkat-push: daemon \(running ? "running" : "installed but not running")")
    } else {
        print("devkat-push: daemon not installed (run: devkat-push --install)")
    }

    let state = SyncState.load()
    print("  sessions synced: \(state.count)")

    // Show last sync from log
    let home = FileManager.default.homeDirectoryForCurrentUser
    let logURL = home.appendingPathComponent(".devkat/daemon.log")
    if let logData = try? String(contentsOf: logURL, encoding: .utf8) {
        let lines = logData.components(separatedBy: "\n").filter { !$0.isEmpty }
        if let last = lines.last {
            print("  last log:  \(last)")
        }
    }

    if loadCredentials() != nil {
        print("  auth:      logged in")
    } else {
        print("  auth:      not logged in (run: devkat-push --login)")
    }
}
