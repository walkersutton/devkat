import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?
    @State private var legalSheet: LegalSheet?

    enum LegalSheet: String, Identifiable {
        case dataPrivacy, terms, privacy
        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                        .padding(.bottom, 4)

                    settingsSection("Data") {
                        row(icon: "arrow.clockwise", label: "Refresh Sessions") {
                            Task { await app.fetchSessions() }
                            dismiss()
                        }
                    }

                    settingsSection("About") {
                        row(icon: "terminal", label: "Devkat") {}
                        divider
                        infoRow(label: "Version", value: appVersion)
                        divider
                        mailRow(label: "Contact", address: "xavier@alleykat.app")
                    }

                    settingsSection("Legal") {
                        navRow(label: "Data & Privacy") {
                            legalSheet = .dataPrivacy
                        }
                        divider
                        navRow(label: "Terms of Service") {
                            legalSheet = .terms
                        }
                        divider
                        navRow(label: "Privacy Policy") {
                            legalSheet = .privacy
                        }
                    }

                    settingsSection("Account") {
                        row(label: "Log Out", color: .red) {
                            app.signOut()
                            dismiss()
                        }
                    }

                    settingsSection("Delete Account") {
                        row(label: "Delete Account", color: .red) {
                            deleteErrorMessage = nil
                            showDeleteConfirmation = true
                        }
                        .disabled(isDeletingAccount)

                        if isDeletingAccount {
                            divider
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(Theme.textDim)
                                Text("Deleting account...")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.textDim)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }

                        if let deleteErrorMessage {
                            divider
                            Text(deleteErrorMessage)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.red.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This permanently deletes your account and all synced session data. This cannot be undone.")
        }
        .sheet(item: $legalSheet) { sheet in
            switch sheet {
            case .dataPrivacy:
                LegalView(title: "Data & Privacy", sections: LegalDocuments.privacyPolicy)
            case .terms:
                LegalView(title: "Terms of Service", sections: LegalDocuments.termsOfService)
            case .privacy:
                LegalView(title: "Privacy Policy", sections: LegalDocuments.privacyPolicy)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("Settings")
                .font(.system(.body, design: .default).weight(.semibold))
                .foregroundStyle(Theme.text)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface)
                        .clipShape(Circle())
                }
                Spacer()
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Section builder

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(hex: 0x1A1A1A))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Row variants

    private func row(icon: String? = nil, label: String, color: Color = Theme.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(color)
                        .frame(width: 22)
                }
                Text(label)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .default))
                .foregroundStyle(Theme.text)
            Spacer()
            Text(value)
                .font(.system(.body, design: .default))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func navRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mailRow(label: String, address: String) -> some View {
        Link(destination: URL(string: "mailto:\(address)")!) {
            HStack {
                Text(label)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(address)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - Helpers

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        deleteErrorMessage = nil

        Task {
            do {
                try await app.deleteAccount()
                await MainActor.run {
                    isDeletingAccount = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .preferredColorScheme(.dark)
}
