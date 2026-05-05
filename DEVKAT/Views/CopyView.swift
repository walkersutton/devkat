import SwiftUI
import UIKit

struct CopyView: View {
    @Environment(AppModel.self) private var app
    @State private var showLayoutPicker = false
    @State private var selectedStatId: String = "duration"
    @State private var toastMessage: String? = nil
    @State private var selectedTab: CopyTab = .activity

    enum CopyTab { case activity, totals }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch selectedTab {
            case .activity:
                if let session = app.selectedSession {
                    content(for: session)
                } else {
                    emptyState
                }
            case .totals:
                VStack(spacing: 0) {
                    header
                    tabBar
                    WeeklyTotalsView(sessions: app.sessions)
                }
            }

            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toastMessage = nil
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private func content(for session: Session) -> some View {
        let allSlots = StatSlot.all(for: session)
        let activeSlot = allSlots.first { $0.id == selectedStatId } ?? allSlots[0]
        let volumeSlot = allSlots.first { $0.id == "volume" }!
        let paceSlot = allSlots.first { $0.id == "pace" }!
        let durationSlot = allSlots.first { $0.id == "duration" }!
        let burnSlot = allSlots.first { $0.id == "burn" }!

        return VStack(spacing: 0) {
            header

            tabBar

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    OverlayTile(
                        slot: activeSlot,
                        isFirst: true,
                        onChevronTap: { showLayoutPicker = true },
                        onCopy: { showToast("Copied!") },
                        onSave: { showToast("Saved!") }
                    )

                    DoubleTile(
                        left: volumeSlot,
                        right: paceSlot,
                        onCopy: { showToast("Copied!") },
                        onSave: { showToast("Saved!") }
                    )

                    TripleTile(
                        slots: [durationSlot, paceSlot, burnSlot],
                        onCopy: { showToast("Copied!") },
                        onSave: { showToast("Saved!") }
                    )

                    MessageTile(
                        session: session,
                        onCopy: { showToast("Copied!") },
                        onSave: { showToast("Saved!") }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .sheet(isPresented: $showLayoutPicker) {
            LayoutPickerSheet(
                session: session,
                selectedStatId: $selectedStatId,
                onSelect: { showLayoutPicker = false }
            )
                .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x1A1A1A))
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .regular))
                Text("TAP TO COPY")
                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                    .tracking(2)
            }
            .foregroundStyle(Theme.text)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10))
                Text("PRESS + HOLD TO SAVE")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(2)
            }
            .foregroundStyle(Theme.textDim)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Activity", tab: .activity)
            tabButton("Totals", tab: .totals)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private func tabButton(_ title: String, tab: CopyTab) -> some View {
        let selected = selectedTab == tab
        return VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(selected ? .white : .clear)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("PICK A SESSION ON HOME")
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.textDim)
                .tracking(2)
            Text("to start composing an overlay")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

// MARK: – Render helper: UIHostingController → UIGraphicsImageRenderer
// Renders at the tile's natural on-screen size so spacing/fonts match exactly,
// then outputs at 6× scale for a large shareable image.

@MainActor
private func renderView<V: View>(_ view: V, size: CGSize) -> UIImage? {
    let hosting = UIHostingController(rootView:
        view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
    )
    hosting.view.frame         = CGRect(origin: .zero, size: size)
    hosting.view.backgroundColor = .clear
    hosting.view.setNeedsLayout()
    hosting.view.layoutIfNeeded()

    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale  = 6   // 6× of natural tile size → large crisp output
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
    }
}

// MARK: – Overlay Tile

private struct OverlayTile: View {
    let slot: StatSlot
    var isFirst: Bool = false
    var onChevronTap: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    private let preset = OverlayPreset.single

    var body: some View {
        preset.view(
            for: slot,
            showChevron: isFirst,
            onChevronTap: onChevronTap
        )
        .aspectRatio(1.6, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { copy() }
        .onLongPressGesture(minimumDuration: 0.4) { save() }
    }

    private func copy() {
        guard let img = render() else { return }
        UIPasteboard.general.image = img
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCopy?()
    }

    private func save() {
        guard let img = render() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onSave?()
    }

    @MainActor
    private func render() -> UIImage? {
        renderView(preset.view(for: slot, export: true), size: CGSize(width: 175, height: 110))
    }
}

// MARK: – Layout Picker Sheet

private struct DoubleTile: View {
    let left: StatSlot
    let right: StatSlot
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    var body: some View {
        AuraDoubleOverlay(left: left, right: right)
            .aspectRatio(1.6, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { copy() }
            .onLongPressGesture(minimumDuration: 0.4) { save() }
    }

    private func copy() {
        guard let img = render() else { return }
        UIPasteboard.general.image = img
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCopy?()
    }

    private func save() {
        guard let img = render() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onSave?()
    }

    @MainActor
    private func render() -> UIImage? {
        renderView(AuraDoubleOverlay(left: left, right: right, export: true), size: CGSize(width: 175, height: 110))
    }
}

// MARK: – Layout Picker Sheet (continued)

private struct TripleTile: View {
    let slots: [StatSlot]
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    var body: some View {
        AuraTripleOverlay(slots: slots)
            .aspectRatio(1.6, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { copy() }
            .onLongPressGesture(minimumDuration: 0.4) { save() }
    }

    private func copy() {
        guard let img = render() else { return }
        UIPasteboard.general.image = img
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCopy?()
    }

    private func save() {
        guard let img = render() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onSave?()
    }

    @MainActor
    private func render() -> UIImage? {
        renderView(AuraTripleOverlay(slots: slots, export: true), size: CGSize(width: 175, height: 110))
    }
}

private struct MessageTile: View {
    let session: Session
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    var body: some View {
        AuraMessageOverlay(session: session)
            .aspectRatio(2.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { copy() }
            .onLongPressGesture(minimumDuration: 0.4) { save() }
    }

    private func copy() {
        guard let img = render() else { return }
        UIPasteboard.general.image = img
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCopy?()
    }

    private func save() {
        guard let img = render() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        onSave?()
    }

    @MainActor
    private func render() -> UIImage? {
        renderView(AuraMessageOverlay(session: session, export: true), size: CGSize(width: 175, height: 88))
    }
}

// MARK: – Layout Picker Sheet (final)

private struct LayoutPickerSheet: View {
    let session: Session
    @Binding var selectedStatId: String
    var onSelect: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(StatSlot.all(for: session)) { slot in
                    StatPill(
                        slot: slot,
                        isSelected: slot.id == selectedStatId
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedStatId = slot.id
                        onSelect()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }
}

private struct StatPill: View {
    let slot: StatSlot
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(slot.label)
                .font(.custom("Baskerville", size: 12))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(slot.formattedValueWithUnit)
                .font(.custom("Baskerville", size: 17))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? .white : Color.white.opacity(0.12), lineWidth: 1)
        )
        .onTapGesture { onTap() }
    }
}

// MARK: – Weekly Totals

private struct WeeklyTotalsView: View {
    let sessions: [Session]

    private var weekSessions: [Session] {
        let cal = Calendar.current
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return sessions.filter { $0.startedAt >= startOfWeek }
    }

    private var totalDuration: TimeInterval {
        weekSessions.reduce(0) { $0 + $1.activeDuration }
    }

    private var totalLinesAdded: Int {
        weekSessions.reduce(0) { $0 + $1.linesAdded }
    }

    private var totalLinesRemoved: Int {
        weekSessions.reduce(0) { $0 + $1.linesRemoved }
    }

    private var totalTokens: Int {
        weekSessions.reduce(0) { $0 + $1.tokens }
    }

    private var weeklyPace: Int {
        let hours = max(totalDuration / 3600, 0.0001)
        return Int(Double(totalLinesAdded + totalLinesRemoved) / hours)
    }

    private var weeklySlots: [StatSlot] {
        [
            StatSlot(id: "duration", label: "Duration",
                     value: SessionFormatting.duration(totalDuration), unit: nil),
            StatSlot(id: "pace",     label: "Pace",
                     value: "\(weeklyPace)", unit: "lines/hr"),
            StatSlot(id: "burn",     label: "Burn",
                     value: SessionFormatting.tokens(totalTokens), unit: totalTokens > 0 ? "tokens" : nil),
        ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                WeeklyTripleTile(slots: weeklySlots)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }
}

// MARK: – Weekly Totals Tile

private struct WeeklyTripleTile: View {
    let slots: [StatSlot]
    @State private var toastMessage: String? = nil

    var body: some View {
        ZStack {
            AuraTripleOverlay(slots: slots, showLabels: false, headerLabel: "This Week")
                .aspectRatio(1.6, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture { copy() }
                .onLongPressGesture(minimumDuration: 0.4) { save() }

            if let msg = toastMessage {
                Text(msg)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
    }

    private func copy() {
        guard let img = render() else { return }
        UIPasteboard.general.image = img
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast("Copied!")
    }

    private func save() {
        guard let img = render() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        showToast("Saved!")
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            toastMessage = nil
        }
    }

    @MainActor
    private func render() -> UIImage? {
        renderView(AuraTripleOverlay(slots: slots, showLabels: false, headerLabel: "This Week", export: true),
                   size: CGSize(width: 175, height: 110))
    }
}
