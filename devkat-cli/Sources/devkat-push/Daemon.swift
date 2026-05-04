import Foundation
import DevKatParser

// Sessions are only marked as "done" once inactive for this long.
// Until then, the daemon re-pushes them every cycle (merge_session handles dedup).
private let coldThreshold: TimeInterval = 4 * 3600 // 4 hours

private func isCold(_ session: ParsedSession) -> Bool {
    Date().timeIntervalSince(session.endedAt) > coldThreshold
}

private func fileIsCold(_ url: URL) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let mod = attrs[.modificationDate] as? Date else { return true }
    return Date().timeIntervalSince(mod) > coldThreshold
}

// MARK: - Sync all sessions across every source

func syncAll(verbose: Bool = false) {
    print("devkat-push: starting sync…"); fflush(stdout)
    guard loadCredentials() != nil else {
        print("devkat-push: not logged in. Run: devkat-push --login")
        exit(1)
    }

    let cutoff = loadInstallTimestamp()
    var state = SyncState.load()
    var pushed = 0
    var failed = 0

    let home = FileManager.default.homeDirectoryForCurrentUser
    let claudeDir = home.appendingPathComponent(".claude")
    let codexDir  = home.appendingPathComponent(".codex")

    // ── Claude sessions ──
    if verbose { print("  scanning claude…"); fflush(stdout) }
    let claudeFiles = findAllSessionFiles(in: claudeDir, since: cutoff)
    for url in claudeFiles {
        let sid = url.deletingPathExtension().lastPathComponent

        // Skip only if file is cold AND already marked
        if state.contains(sid) && fileIsCold(url) { continue }

        do {
            let sessions = try parseSessions(at: url)
            for session in sessions {
                guard session.tokens > 0, session.activeDuration >= 60 else { continue }
                if state.contains(session.id) && isCold(session) { continue }

                try writeSession(session)
                pushed += 1
                if verbose { printSyncLine(session) }

                if isCold(session) { state.mark(session.id) }
            }
            if fileIsCold(url) { state.mark(sid) }
        } catch {
            failed += 1
            if verbose { print("  ✗ claude/\(sid.prefix(8))… \(error.localizedDescription)") }
        }
    }

    // ── Codex sessions ──
    if verbose { print("  scanning codex…"); fflush(stdout) }
    let codexRows = findAllCodexSessions(in: codexDir, since: cutoff)
    for row in codexRows {
        let sessions = parseCodexSessions(row)
        let allCold = sessions.allSatisfy { isCold($0) }
        if state.contains(row.id) && allCold { continue }

        for session in sessions {
            guard session.tokens > 0, session.activeDuration >= 60 else { continue }
            if state.contains(session.id) && isCold(session) { continue }

            do {
                try writeSession(session)
                pushed += 1
                if verbose { printSyncLine(session) }

                if isCold(session) { state.mark(session.id) }
            } catch {
                failed += 1
                if verbose { print("  ✗ codex/\(row.id.prefix(8))… \(error.localizedDescription)") }
            }
        }
        if allCold { state.mark(row.id) }
    }

    // ── Cursor sessions ──
    if verbose { print("  scanning cursor…"); fflush(stdout) }
    let cursorRows = findAllCursorSessions(since: cutoff)
    for row in cursorRows {
        let sessions = parseCursorSessions(row)
        let allCold = sessions.allSatisfy { isCold($0) }
        if state.contains(row.composerId) && allCold { continue }

        for session in sessions {
            guard session.linesAdded + session.linesRemoved > 0, session.activeDuration >= 60 else { continue }
            if state.contains(session.id) && isCold(session) { continue }

            do {
                try writeSession(session)
                pushed += 1
                if verbose { printSyncLine(session) }

                if isCold(session) { state.mark(session.id) }
            } catch {
                failed += 1
                if verbose { print("  ✗ cursor/\(row.composerId.prefix(8))… \(error.localizedDescription)") }
            }
        }
        if allCold { state.mark(row.composerId) }
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
    writeInstallTimestamp()
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
            <string>\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb</string>
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
        print("  interval: every 5 min + on Codex/Cursor activity")
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
