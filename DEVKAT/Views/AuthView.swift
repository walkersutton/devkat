import SwiftUI

struct AuthView: View {
    var onAuthenticated: () -> Void

    @State private var email    = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        PixelKat(pixelSize: 3, color: Theme.logoGreen)
                        PixelText(text: "DEVKAT", pixelSize: 3, color: Theme.logoGreen)
                    }
                    Text("hello, sharing")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.bottom, 40)

                // Manifesto
                manifesto
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)

                // Form
                VStack(spacing: 12) {
                    field(placeholder: "Email", text: $email, keyboard: .emailAddress)
                    field(placeholder: "Password", text: $password, secure: true)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Button(action: submit) {
                        ZStack {
                            if isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text(isSignUp ? "CREATE ACCOUNT" : "SIGN IN")
                                    .font(.system(.footnote, design: .monospaced).weight(.bold))
                                    .tracking(2)
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.logoGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .padding(.top, 8)

                    Button {
                        isSignUp.toggle()
                        errorMessage = nil
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign in" : "No account? Create one")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
                Spacer()
            }
        }
    }

    private var manifesto: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Developers ship things worth sharing.")
                .font(.custom("TimesNewRomanPS-ItalicMT", size: 24))
                .foregroundStyle(Theme.text)
            Text("I wanted a systematic record of my sessions — the hours, the lines, the token burn — and a way to share it that matched the craft.")
                .font(.custom("TimesNewRomanPS-ItalicMT", size: 20))
                .foregroundStyle(Theme.textDim)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let tokens: AuthTokens
                if isSignUp {
                    tokens = try await SupabaseService.shared.signUp(email: email, password: password)
                } else {
                    tokens = try await SupabaseService.shared.signIn(email: email, password: password)
                }
                tokens.persist()
                await MainActor.run { onAuthenticated() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

