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
        .onAppear { StickerGenerator.logFonts() }
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

// MARK: – Sticker Generator (UIGraphicsImageRenderer — no SwiftUI/ImageRenderer)

private enum StickerGenerator {

    private static let size    = CGSize(width: 1080, height: 1080)
    private static let white   = UIColor.white
    private static let dim     = UIColor.white  // labels same opacity as values
    private static let blue    = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
    private static let margin: CGFloat = 72
    private static let labelFont: UIFont = {
        let f = UIFont(name: "Baskerville-Bold", size: 36)
        print("[StickerGenerator] labelFont: \(f?.fontName ?? "⚠️ FALLBACK – Baskerville-Bold not found")")
        return f ?? .boldSystemFont(ofSize: 36)
    }()
    private static let valueFont: UIFont = {
        let f = UIFont(name: "Baskerville-BoldItalic", size: 96)
        print("[StickerGenerator] valueFont: \(f?.fontName ?? "⚠️ FALLBACK – Baskerville-BoldItalic not found")")
        return f ?? .boldSystemFont(ofSize: 96)
    }()
    private static let unitFont: UIFont = {
        let f = UIFont(name: "Baskerville-Bold", size: 32)
        print("[StickerGenerator] unitFont:  \(f?.fontName ?? "⚠️ FALLBACK – Baskerville-Bold not found")")
        // Dump all available Baskerville faces once
        let families = UIFont.familyNames.filter { $0.lowercased().contains("baskerville") }
        for family in families {
            print("[StickerGenerator] Baskerville family '\(family)' faces: \(UIFont.fontNames(forFamilyName: family))")
        }
        return f ?? .boldSystemFont(ofSize: 32)
    }()

    /// Call once on screen appear to force lazy statics to init and print logs.
    static func logFonts() {
        _ = labelFont; _ = valueFont; _ = unitFont
    }

    // Transparent 1080×1080 canvas
    private static func makeRenderer() -> UIGraphicsImageRenderer {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt)
    }

    // Single stat — large centred value + label above
    static func single(label: String, value: String, unit: String?) -> UIImage {
        makeRenderer().image { ctx in
            ctx.cgContext.clear(CGRect(origin: .zero, size: size))

            let combined = unit.map { "\(value) \($0)" } ?? value
            let valStr  = NSAttributedString(string: combined, attributes: [.font: valueFont, .foregroundColor: white])
            let lblStr  = NSAttributedString(string: label.uppercased(), attributes: [.font: labelFont, .foregroundColor: white, .kern: 3.0])

            let cx = size.width / 2
            let valSz = valStr.size()
            let lblSz = lblStr.size()
            let gap: CGFloat = 16
            let totalH = lblSz.height + gap + valSz.height
            var y = (size.height - totalH) / 2

            lblStr.draw(at: CGPoint(x: cx - lblSz.width / 2, y: y))
            y += lblSz.height + gap
            valStr.draw(at: CGPoint(x: cx - valSz.width / 2, y: y))
        }
    }

    // Two stats side by side
    static func double(left: StatSlot, right: StatSlot) -> UIImage {
        makeRenderer().image { ctx in
            ctx.cgContext.clear(CGRect(origin: .zero, size: size))
            let slots = [left, right]
            let colW = (size.width - margin * 2 - 48) / 2
            for (i, slot) in slots.enumerated() {
                let x = margin + CGFloat(i) * (colW + 48)
                drawStatColumn(slot: slot, x: x, colW: colW, ctx: ctx.cgContext)
            }
        }
    }

    // Three stats side by side
    static func triple(slots: [StatSlot], headerLabel: String? = nil) -> UIImage {
        let triLabelFont = UIFont(name: "Baskerville-Bold", size: 26) ?? .boldSystemFont(ofSize: 26)
        let triValueFont = UIFont(name: "Baskerville-BoldItalic", size: 68) ?? .boldSystemFont(ofSize: 68)
        let triUnitFont  = UIFont(name: "Baskerville-Bold", size: 22) ?? .boldSystemFont(ofSize: 22)
        return makeRenderer().image { ctx in
            ctx.cgContext.clear(CGRect(origin: .zero, size: size))
            let spacing: CGFloat = 32
            let colW = (size.width - margin * 2 - spacing * 2) / 3
            for (i, slot) in slots.prefix(3).enumerated() {
                let x = margin + CGFloat(i) * (colW + spacing)
                drawStatColumn(slot: slot, x: x, colW: colW, ctx: ctx.cgContext,
                               headerLabel: i == 0 ? headerLabel : nil,
                               labelFont: triLabelFont, valueFont: triValueFont, unitFont: triUnitFont)
            }
        }
    }

    // iMessage-style bubble
    static func message(session: Session) -> UIImage {
        makeRenderer().image { ctx in
            ctx.cgContext.clear(CGRect(origin: .zero, size: size))

            let burn = session.tokens > 0
                ? "\(SessionFormatting.tokens(session.tokens)) tokens" : "—"
            let df = DateFormatter(); df.dateFormat = "HH:mm"
            let bubbleText = "\(SessionFormatting.duration(session.activeDuration)), \(burn)"
            let subText    = "Claude Monkey \(df.string(from: session.startedAt))"

            let bubbleFont = UIFont.systemFont(ofSize: 52, weight: .bold)
            let subFont    = UIFont.systemFont(ofSize: 36, weight: .bold)

            let bubbleStr = NSAttributedString(string: bubbleText, attributes: [.font: bubbleFont, .foregroundColor: UIColor.white])
            let subStr    = NSAttributedString(string: subText, attributes: [.font: subFont, .foregroundColor: UIColor.white.withAlphaComponent(0.8)])

            let pad: CGFloat = 44
            let bubbleSz = bubbleStr.size()
            let subSz    = subStr.size()
            let bubbleW  = bubbleSz.width + pad * 2
            let bubbleH  = bubbleSz.height + pad

            // Right-aligned bubble in lower-centre
            let bubbleX = size.width - margin - bubbleW
            let bubbleY = size.height / 2 - bubbleH / 2

            let bubbleRect = CGRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH)
            let path = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 28)
            blue.setFill(); path.fill()

            bubbleStr.draw(at: CGPoint(
                x: bubbleX + pad,
                y: bubbleY + (bubbleH - bubbleSz.height) / 2))

            subStr.draw(at: CGPoint(
                x: size.width - margin - subSz.width,
                y: bubbleY + bubbleH + 16))
        }
    }

    // Helper: draw a label + value column at x
    private static func drawStatColumn(slot: StatSlot, x: CGFloat, colW: CGFloat,
                                        ctx: CGContext, headerLabel: String? = nil,
                                        labelFont lf: UIFont? = nil,
                                        valueFont vf: UIFont? = nil,
                                        unitFont uf: UIFont? = nil) {
        let lFont = lf ?? labelFont
        let vFont = vf ?? valueFont
        let uFont = uf ?? unitFont
        // Combine value + unit on one line (matching the UI's formattedValueWithUnit)
        let combined = slot.unit.map { "\(slot.value) \($0)" } ?? slot.value
        let valStr  = NSAttributedString(string: combined, attributes: [.font: vFont, .foregroundColor: white])
        let lblStr  = NSAttributedString(string: slot.label.uppercased(), attributes: [.font: lFont, .foregroundColor: white, .kern: 2.0])
        let hdrStr  = headerLabel.map { NSAttributedString(string: $0, attributes: [.font: uFont, .foregroundColor: white]) }

        let gap: CGFloat = 14
        let valSz = valStr.size()
        let lblSz = lblStr.size()
        let hdrH  = hdrStr.map  { $0.size().height + gap } ?? 0
        let totalH = hdrH + lblSz.height + gap + valSz.height
        var y = (size.height - totalH) / 2

        hdrStr.flatMap { s -> () in s.draw(at: CGPoint(x: x, y: y)); y += hdrH }
        lblStr.draw(at: CGPoint(x: x, y: y));  y += lblSz.height + gap
        valStr.draw(at: CGPoint(x: x, y: y))
    }

}

// MARK: – Shared render helper (now just a thin shim)

@MainActor
private func renderOverlay<V: View>(_ content: V, size: CGSize, scale: CGFloat = 8) -> UIImage? {
    let anchored = ZStack {
        Rectangle().fill(Color.clear)
            .frame(width: size.width, height: size.height)
        content
    }
    .environment(\.colorScheme, .dark)

    let renderer = ImageRenderer(content: anchored)
    renderer.scale = scale
    renderer.isOpaque = false
    return renderer.uiImage
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
        StickerGenerator.single(label: slot.label, value: slot.value, unit: slot.unit)
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
        StickerGenerator.double(left: left, right: right)
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
        StickerGenerator.triple(slots: slots)
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
        StickerGenerator.message(session: session)
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
        StickerGenerator.triple(slots: slots, headerLabel: "This Week")
    }
}
