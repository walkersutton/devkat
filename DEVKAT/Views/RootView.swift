import SwiftUI
import StoreKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var selected: Tab = .home
    @State private var showNegativeFeedback = false
    @State private var feedbackMessage = ""

    enum Tab: String, CaseIterable, Hashable {
        case home, copy

        var selectedIcon: String {
            switch self {
            case .home: "house.fill"
            case .copy: "plus.square.on.square.fill"
            }
        }

        var unselectedIcon: String {
            switch self {
            case .home: "house"
            case .copy: "plus.square.on.square"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            ZStack {
                HomeView(
                    onCopyTap: {
                        selectTab(.copy)
                    },
                    onSessionTap: { session in
                        app.selectedSession = session
                        selected = .copy
                    }
                )
                .opacity(selected == .home ? 1 : 0)
                .allowsHitTesting(selected == .home)

                CopyView()
                    .opacity(selected == .copy ? 1 : 0)
                    .allowsHitTesting(selected == .copy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .sheet(
            isPresented: Binding(
                get: { app.shouldShowReviewPrompt },
                set: { if !$0 { app.shouldShowReviewPrompt = false } }
            )
        ) {
            ReviewPromptSheet(
                onNo: {
                    app.recordNegativeReviewIntent()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showNegativeFeedback = true
                    }
                },
                onYes: {
                    Task {
                        await app.recordPositiveReviewIntent()
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        await MainActor.run {
                            requestAppReview()
                        }
                    }
                }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x1A1A1A))
        }
        .sheet(isPresented: $showNegativeFeedback) {
            NegativeReviewFeedbackSheet(
                message: $feedbackMessage,
                onCancel: {
                    feedbackMessage = ""
                    showNegativeFeedback = false
                },
                onSubmit: {
                    let message = feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                    feedbackMessage = ""
                    showNegativeFeedback = false
                    Task {
                        await app.submitNegativeReviewFeedback(message)
                    }
                }
            )
            .presentationDetents([.height(350)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x1A1A1A))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 0.5)

            HStack(spacing: 72) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectTab(tab)
                    } label: {
                        Image(systemName: selected == tab ? tab.selectedIcon : tab.unselectedIcon)
                            .font(.system(size: 22, weight: selected == tab ? .medium : .light))
                            .foregroundStyle(selected == tab
                                             ? .white
                                             : Color.white.opacity(0.45))
                            .frame(width: 56, height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack {
                BlurView(style: .systemMaterialDark)
                Color.black.opacity(0.4)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func selectTab(_ tab: Tab) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            selected = tab
        }
    }

    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }
        SKStoreReviewController.requestReview(in: scene)
    }
}

private struct ReviewPromptSheet: View {
    let onNo: () -> Void
    let onYes: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Do you f*cking love Devkat?")
                    .font(.system(size: 17, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Be honest. This helps us make Devkat better.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    onNo()
                } label: {
                    Text("H*ll no.")
                        .font(.system(size: 13, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    onYes()
                } label: {
                    Text("F*ck yes!")
                        .font(.system(size: 13, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.logoGreen)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
    }
}

private struct NegativeReviewFeedbackSheet: View {
    @Binding var message: String
    let onCancel: () -> Void
    let onSubmit: () -> Void

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Why do you hate me?")
                    .font(.system(size: 17, design: .monospaced).weight(.bold))
                    .foregroundStyle(.white)

                Text("Tell us what broke, annoyed you, or needs to be better.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }

            TextEditor(text: $message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 112)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, design: .monospaced).weight(.medium))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Button {
                    onSubmit()
                } label: {
                    Text("Send feedback")
                        .font(.system(size: 13, design: .monospaced).weight(.semibold))
                        .foregroundStyle(canSubmit ? .black : Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canSubmit ? Theme.logoGreen : Color.white.opacity(0.06))
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
