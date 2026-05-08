import SwiftUI
import OSLog

struct HomeView: View {
    private static let log = Logger(subsystem: "app.devkat.ios", category: "HomeView")

    var onCopyTap: () -> Void = {}
    var onSessionTap: (Session) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @State private var showSettings = false
    @State private var copiedCommand = false
    @State private var pulse = false
    @State private var checkedNotConnected = false
    @State private var showSetupInfo = false
    @State private var showUpdatePrompt = false
    @State private var copiedUpdateCommand = false

    private var grouped: [(label: String, items: [Session])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: app.sessions) { cal.startOfDay(for: $0.startedAt) }
        return dict
            .sorted { $0.key > $1.key }
            .map { (SessionFormatting.dayLabel(for: $0.key), $0.value.sorted { $0.startedAt > $1.startedAt }) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(Theme.border)
            if !app.leaderboard.isEmpty {
                leaderboardStrip
            }
            if app.sessions.isEmpty {
                if app.installations.isEmpty {
                    setupState
                } else {
                    waitingState
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24, pinnedViews: []) {
                        ForEach(grouped, id: \.label) { group in
                            section(label: group.label, items: group.items)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 100)
                }
                .refreshable { await app.fetchSessions() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(app)
        }
        .sheet(isPresented: $showSetupInfo) {
            SetupInfoSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x1A1A1A))
        }
        .sheet(isPresented: $showUpdatePrompt) {
            CLIUpdateSheet(
                version: app.availableCLIUpdate ?? "",
                copied: $copiedUpdateCommand,
                onDismiss: {
                    Self.log.info("cli_update_prompt_dismiss_tapped version=\(app.availableCLIUpdate ?? "unknown", privacy: .public)")
                    app.dismissCLIUpdate()
                    showUpdatePrompt = false
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x1A1A1A))
        }
        .onAppear {
            if let version = app.availableCLIUpdate {
                Self.log.info("cli_update_prompt_presented_on_appear version=\(version, privacy: .public)")
                showUpdatePrompt = true
            }
        }
        .onChange(of: app.availableCLIUpdate) { _, newValue in
            if let newValue {
                Self.log.info("cli_update_prompt_presented_on_change version=\(newValue, privacy: .public)")
                showUpdatePrompt = true
            } else if showUpdatePrompt {
                Self.log.info("cli_update_prompt_auto_closed reason=version_resolved")
                showUpdatePrompt = false
            }
        }
        .task(id: showUpdatePrompt) {
            guard showUpdatePrompt else { return }
            Self.log.info("cli_update_poll_started")
            while showUpdatePrompt {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard showUpdatePrompt else { break }
                Self.log.info("cli_update_poll_refreshing")
                await app.fetchSessions()
            }
            Self.log.info("cli_update_poll_stopped")
        }
    }

    private var titleBar: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Button {
                showSetupInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(alignment: .center, spacing: 8) {
                Text("DEVKAT")
                    .font(.custom("LEDLIGHT", size: 24).weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            Button {
                onCopyTap()
            } label: {
                Image(systemName: "plus.square.on.square")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var waitingState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(Theme.logoGreen.opacity(0.4), lineWidth: 1)
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulse ? 1.4 : 1.0)
                    .opacity(pulse ? 0 : 0.8)
                Image(systemName: "terminal")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(Theme.logoGreen)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            Text("CONNECTED")
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.logoGreen)
                .tracking(2)
            VStack(spacing: 6) {
                if let host = app.installations.first?.hostname {
                    Text(host)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
                Text("Waiting for your first session…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
            }
            Text("Run Claude, Codex, or Cursor on this Mac\nand sessions will sync automatically.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            refreshButton(label: "REFRESH")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setupState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Theme.textDim)
            HStack(spacing: 8) {
                Text("SETUP")
                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textDim)
                    .tracking(2)
                Button {
                    showSetupInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.logoGreen)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 10) {
                Text("Paste this in your terminal:")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                VStack(spacing: 8) {
                    Text("curl -fsSL https://raw.githubusercontent.com/runnon/devkat-releases/main/install.sh | sh")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .tint(Theme.textMuted)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if copiedCommand {
                        Text("COPIED")
                            .font(.system(size: 10, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.logoGreen)
                            .tracking(1.5)
                    } else {
                        Text("TAP HERE TO COPY")
                            .font(.system(size: 10, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.logoGreen)
                            .tracking(1.5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIPasteboard.general.string = "curl -fsSL https://raw.githubusercontent.com/runnon/devkat-releases/main/install.sh | sh"
                    copiedCommand = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCommand = false }
                }
            }
            .padding(.horizontal, 20)
            Text("Sessions from Claude, Codex, and Cursor\nwill sync automatically.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            if checkedNotConnected {
                Text("Not connected yet. Run the command above.")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .foregroundStyle(.red.opacity(0.8))
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            checkConnectionButton
            Spacer(minLength: 0)
        }
        .padding(.bottom, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var checkConnectionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            checkedNotConnected = false
            Task {
                await app.fetchSessions()
                if app.installations.isEmpty {
                    withAnimation { checkedNotConnected = true }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if app.isLoadingSessions {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.logoGreen)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(app.isLoadingSessions ? "CHECKING…" : "CHECK CONNECTION")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(1.5)
            }
            .foregroundStyle(Theme.logoGreen)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.logoGreen.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(app.isLoadingSessions)
        .padding(.top, 8)
    }

    private func refreshButton(label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await app.fetchSessions() }
        } label: {
            HStack(spacing: 8) {
                if app.isLoadingSessions {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.logoGreen)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(app.isLoadingSessions ? "CHECKING…" : label)
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(1.5)
            }
            .foregroundStyle(Theme.logoGreen)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.logoGreen.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(app.isLoadingSessions)
        .padding(.top, 8)
    }

    private func section(label: String, items: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(label.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textDim)
                    .tracking(2)
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { session in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSessionTap(session)
                    } label: {
                        SessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var leaderboardStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("TOP TOKEN BURNERS")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textMuted)
                    .tracking(1.5)
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            .padding(.horizontal, 16)

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(app.leaderboard.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        leaderboardEntry(index: index, entry: entry)
                            .frame(
                                width: proxy.size.width * leaderboardColumnWidth(for: index),
                                alignment: leaderboardFrameAlignment(for: index)
                            )
                    }
                }
            }
            .frame(height: 32)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }

    private func leaderboardEntry(index: Int, entry: LeaderboardEntry) -> some View {
        let alignment: HorizontalAlignment = index == 0 ? .leading : index == 1 ? .center : .trailing
        return VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                    .foregroundStyle(index == 0 ? Theme.logoGreen : Theme.textDim)
                    .fixedSize()
                Text(entry.displayName)
                    .font(.system(size: 11, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(leaderboardIcon(for: index))
                    .font(.system(size: 12))
                    .fixedSize()
            }
            .fixedSize(horizontal: true, vertical: false)

            Text(entry.formattedTokens)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func leaderboardColumnWidth(for index: Int) -> CGFloat {
        index == 1 ? 0.46 : 0.27
    }

    private func leaderboardFrameAlignment(for index: Int) -> Alignment {
        index == 0 ? .leading : index == 1 ? .center : .trailing
    }

    private func leaderboardIcon(for index: Int) -> String {
        switch index {
        case 0: return "🦁"
        case 1: return "🐆"
        default: return "🐈"
        }
    }

}

private struct SetupInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How it works")
                .font(.system(.body, design: .default).weight(.semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                infoBlock(
                    icon: "terminal",
                    title: "Local CLI daemon",
                    body: "The curl command installs devkat-push, a lightweight background daemon that runs on your Mac."
                )

                infoBlock(
                    icon: "chart.bar",
                    title: "Tracks AI usage stats",
                    body: "It watches your Claude, Codex, and Cursor sessions and computes aggregate stats — duration, lines changed, tokens burned, and files touched."
                )

                infoBlock(
                    icon: "lock.shield",
                    title: "No code leaves your machine",
                    body: "Only numbers are synced. No source code, file paths, prompts, or responses are ever transmitted."
                )

                infoBlock(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Syncs to this app",
                    body: "Stats push to your Devkat account so you can view session history and create shareable overlay cards."
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoBlock(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.logoGreen)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - CLI Update Sheet

private struct CLIUpdateSheet: View {
    private static let log = Logger(subsystem: "app.devkat.ios", category: "CLIUpdateSheet")

    let version: String
    @Binding var copied: Bool
    let onDismiss: () -> Void

    private let command = "curl -fsSL https://raw.githubusercontent.com/runnon/devkat-releases/main/install.sh | sh"

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.logoGreen)

                Text("CLI Update Available")
                    .font(.system(size: 15, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)

                Text("Version \(version) is ready. Run this in your terminal:")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }

            Button {
                UIPasteboard.general.string = command
                copied = true
                Self.log.info("cli_update_command_copied version=\(self.version, privacy: .public)")
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                VStack(spacing: 6) {
                    Text(command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)

                    Text(copied ? "Copied!" : "Tap to copy")
                        .font(.system(size: 12, design: .monospaced).weight(.medium))
                        .foregroundStyle(Theme.logoGreen)
                }
            }
            .buttonStyle(.plain)

            Button {
                onDismiss()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 13, design: .monospaced).weight(.medium))
                    .foregroundStyle(Theme.textDim)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
        .preferredColorScheme(.dark)
}
