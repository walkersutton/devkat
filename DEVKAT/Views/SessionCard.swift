import SwiftUI

struct SessionCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Theme.border).padding(.top, 14)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("DURATION")
                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textMuted)
                    .tracking(2)
                Text(SessionFormatting.duration(session.activeDuration))
                    .font(.system(size: 44, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 0) {
                    stat(label: "VOLUME",
                         value: "\(session.linesAdded + session.linesRemoved)",
                         unit: "lines")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    stat(label: "PACE",
                         value: "\(session.linesPerHour)",
                         unit: "lines/hr")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 0) {
                    stat(label: "SCOPE",
                         value: "\(session.filesTouched)",
                         unit: "files")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    stat(label: "BURN",
                         value: SessionFormatting.tokens(session.tokens),
                         unit: "tokens")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .aspectRatio(1.35, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(">")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Text(SessionFormatting.dayLabel(for: session.startedAt).uppercased())
                .font(.system(size: 11, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.textDim)
                .tracking(1.5)
            Spacer(minLength: 4)
        }
    }

    private func stat(label: String, value: String, unit: String? = nil) -> some View {
        let display = unit.map { "\(value) \($0)" } ?? value
        return VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.textMuted)
                .tracking(1.5)
            Text(display)
                .font(.system(size: 18, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }
}

#Preview {
    let session = Session(
        id: "preview-session",
        startedAt: Date().addingTimeInterval(-8040),
        endedAt: Date(),
        activeDuration: 8040,
        linesAdded: 842, linesRemoved: 137,
        filesTouched: 12, tokens: 18_400,
        sources: ["claude", "codex"],
        models: ["claude-opus-4-5", "gpt-5"],
        repoAlias: "devkat", gitBranch: "main"
    )
    ZStack {
        Theme.background.ignoresSafeArea()
        SessionCard(session: session)
            .padding()
    }
}
