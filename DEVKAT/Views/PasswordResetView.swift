import SwiftUI
import PostHog

struct PasswordResetView: View {
    var initialEmail: String
    var onCancel: () -> Void
    var onAuthenticated: () -> Void

    private enum Step {
        case enterEmail
        case enterCode
        case enterNewPassword
    }

    @State private var step: Step = .enterEmail
    @State private var email: String
    @State private var code: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var recoveryTokens: AuthTokens?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var info: String?

    init(initialEmail: String, onCancel: @escaping () -> Void, onAuthenticated: @escaping () -> Void) {
        self.initialEmail = initialEmail
        self.onCancel = onCancel
        self.onAuthenticated = onAuthenticated
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(title)
                            .font(.custom("TimesNewRomanPS-ItalicMT", size: 26))
                            .foregroundStyle(Theme.text)
                        Text(subtitle)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 48)
                    .padding(.bottom, 24)

                    VStack(spacing: 12) {
                        formFields

                        if let info {
                            Text(info)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
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
                                    Text(buttonLabel)
                                        .font(.system(.footnote, design: .monospaced).weight(.bold))
                                        .tracking(2)
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(.white.opacity(canSubmit ? 1.0 : 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isLoading)
                        .padding(.top, 8)

                        if step == .enterCode {
                            Button {
                                sendCode(initial: false)
                            } label: {
                                Text("Resend code")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.textDim)
                            }
                            .disabled(isLoading)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Text("CANCEL")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var title: String {
        switch step {
        case .enterEmail:       return "Reset your password."
        case .enterCode:        return "Check your email."
        case .enterNewPassword: return "Set a new password."
        }
    }

    private var subtitle: String {
        switch step {
        case .enterEmail:
            return "Enter the email you use to sign in. We'll send you a 6-digit code."
        case .enterCode:
            return "We sent a 6-digit code to \(email). Enter it below to continue."
        case .enterNewPassword:
            return "Pick a new password (at least 6 characters). You'll be signed in once it's saved."
        }
    }

    private var buttonLabel: String {
        switch step {
        case .enterEmail:       return "SEND CODE"
        case .enterCode:        return "VERIFY CODE"
        case .enterNewPassword: return "SAVE PASSWORD"
        }
    }

    private var canSubmit: Bool {
        switch step {
        case .enterEmail:       return !email.isEmpty
        case .enterCode:        return code.count == 6
        case .enterNewPassword: return newPassword.count >= 6 && newPassword == confirmPassword
        }
    }

    @ViewBuilder
    private var formFields: some View {
        switch step {
        case .enterEmail:
            field(placeholder: "Email", text: $email, keyboard: .emailAddress)
        case .enterCode:
            field(placeholder: "6-digit code", text: $code, keyboard: .numberPad, contentType: .oneTimeCode)
                .onChange(of: code) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    let clipped = String(digits.prefix(6))
                    if clipped != newValue {
                        code = clipped
                    }
                    if clipped.count == 6 && !isLoading {
                        verifyCode()
                    }
                }
        case .enterNewPassword:
            field(placeholder: "New password", text: $newPassword, secure: true, contentType: .newPassword)
            field(placeholder: "Confirm password", text: $confirmPassword, secure: true, contentType: nil)
        }
    }

    private func field(placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default, secure: Bool = false, contentType: UITextContentType? = nil) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
                    .textContentType(contentType)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(contentType)
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
        errorMessage = nil
        info = nil
        switch step {
        case .enterEmail:
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "Enter your email to continue."
                return
            }
            sendCode(initial: true)
        case .enterCode:
            guard code.count == 6 else {
                errorMessage = "Enter the 6-digit code from your email."
                return
            }
            verifyCode()
        case .enterNewPassword:
            savePassword()
        }
    }

    private func sendCode(initial: Bool) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        email = trimmed
        isLoading = true
        errorMessage = nil
        info = nil
        PostHogSDK.shared.capture("password_reset_code_requested")

        Task {
            do {
                try await SupabaseService.shared.sendPasswordResetCode(email: trimmed)
                await MainActor.run {
                    isLoading = false
                    step = .enterCode
                    if !initial { info = "New code sent." }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func verifyCode() {
        isLoading = true
        Task {
            do {
                let tokens = try await SupabaseService.shared.verifyPasswordResetCode(email: email, code: code)
                await MainActor.run {
                    recoveryTokens = tokens
                    isLoading = false
                    step = .enterNewPassword
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Invalid or expired code. Try again."
                }
            }
        }
    }

    private func savePassword() {
        guard let tokens = recoveryTokens else {
            errorMessage = "Session expired. Start over."
            step = .enterEmail
            return
        }
        guard newPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }

        isLoading = true
        Task {
            do {
                try await SupabaseService.shared.updatePassword(newPassword, accessToken: tokens.accessToken)
                tokens.persist()
                PostHogSDK.shared.capture("password_reset_completed")
                PostHogSDK.shared.identify(email, userProperties: ["email": email])
                await MainActor.run {
                    onAuthenticated()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
