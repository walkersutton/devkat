import SwiftUI

struct StatSlot: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let unit: String?

    // Time values have no unit (nil) so they render as-is.
    // All other units get a space: "18.4k tokens", "437 lines/hr".
    var formattedValueWithUnit: String {
        guard let unit else { return value }
        return "\(value) \(unit)"
    }
}

extension StatSlot {
    static func all(for session: Session) -> [StatSlot] {
        [
            StatSlot(id: "duration", label: "Duration",
                     value: SessionFormatting.duration(session.activeDuration), unit: nil),
            StatSlot(id: "pace", label: "Pace",
                     value: "\(session.linesPerHour)", unit: "lines/hr"),
            StatSlot(id: "scope", label: "Scope",
                     value: "\(session.filesTouched)", unit: "files"),
            StatSlot(id: "volume", label: "Volume",
                     value: "\(session.linesAdded + session.linesRemoved)", unit: "lines"),
            StatSlot(id: "burn", label: "Burn",
                     value: SessionFormatting.tokens(session.tokens), unit: session.tokens > 0 ? "tokens" : nil),
        ]
    }
}

struct AuraOverlay: View {
    let slot: StatSlot
    var showChevron: Bool = false
    var onChevronTap: (() -> Void)?
    var export: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text(slot.label)
                    .font(.custom("Baskerville", size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(slot.formattedValueWithUnit)
                    .font(.custom("Baskerville", size: 17))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showChevron {
                Button {
                    onChevronTap?()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
            }
        }
        .background(export ? Color.clear : Theme.surface)
    }
}

struct AuraDoubleOverlay: View {
    let left: StatSlot
    let right: StatSlot
    var export: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            statColumn(left)
            statColumn(right)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(export ? Color.clear : Theme.surface)
    }

    private func statColumn(_ slot: StatSlot) -> some View {
        VStack(spacing: 3) {
            Text(slot.label)
                .font(.custom("Baskerville", size: 10))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(slot.formattedValueWithUnit)
                .font(.custom("Baskerville", size: 14))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AuraTripleOverlay: View {
    let slots: [StatSlot]
    var showLabels: Bool = true
    var headerLabel: String? = nil
    var export: Bool = false

    var body: some View {
        if let headerLabel {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerLabel)
                    .font(.custom("Baskerville", size: 8))
                    .foregroundStyle(Color.white.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    ForEach(slots) { slot in
                        Text(slot.formattedValueWithUnit)
                            .font(.custom("Baskerville", size: 10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(export ? Color.clear : Theme.surface)
        } else {
            HStack(spacing: 0) {
                ForEach(slots) { slot in
                    VStack(spacing: 2) {
                        if showLabels {
                            Text(slot.label)
                                .font(.custom("Baskerville", size: 7))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        Text(slot.formattedValueWithUnit)
                            .font(.custom("Baskerville", size: 10))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(export ? Color.clear : Theme.surface)
        }
    }
}

struct AuraMessageOverlay: View {
    let session: Session
    var export: Bool = false

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: session.startedAt)
    }

    private var bubbleText: String {
        let burn = session.tokens > 0 ? "\(SessionFormatting.tokens(session.tokens)) tokens" : "—"
        return "\(SessionFormatting.duration(session.activeDuration)), \(burn)"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                Text(bubbleText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(hex: 0x007AFF))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("Claude Monkey \(timeString)")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.4))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .background(export ? Color.clear : Theme.surface)
    }
}
