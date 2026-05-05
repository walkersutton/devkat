import SwiftUI

struct HomeView: View {
    var onCopyTap: () -> Void = {}
    var onSessionTap: (Session) -> Void = { _ in }

    @Environment(AppModel.self) private var app
    @State private var showSettings = false
    @State private var copiedCommand = false

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
            if app.sessions.isEmpty {
                emptyState
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

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(Theme.textDim)
            Text("SETUP")
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.textDim)
                .tracking(2)
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
            Spacer()
        }
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
}

#Preview {
    HomeView()
        .environment(AppModel())
        .preferredColorScheme(.dark)
}
