import Foundation
import Observation
import UIKit

@Observable
final class AppModel {
    var selectedSession: Session?
    var sessions: [Session] = []
    var installations: [Installation] = []
    var leaderboard: [LeaderboardEntry] = []
    var isLoggedIn: Bool = AuthTokens.stored != nil
    var isLoadingSessions = false
    var availableCLIUpdate: String?
    var shouldShowReviewPrompt = false

    init() {
        ReviewPromptState.recordAppOpen()
        if isLoggedIn { Task { await fetchSessions() } }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isLoggedIn else { return }
            Task { await self.fetchSessions() }
        }
    }

    // MARK: - CLI Update Check

    /// Compares the user's installed CLI version (from installations table)
    /// against the latest GitHub release. Shows update prompt if outdated.
    @MainActor
    func checkForCLIUpdate() async {
        guard let url = URL(string: "https://api.github.com/repos/runnon/devkat-releases/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

        struct Release: Decodable { let tag_name: String }
        guard let release = try? JSONDecoder().decode(Release.self, from: data) else { return }

        let latestTag = release.tag_name
        let latestVersion = latestTag.hasPrefix("v") ? String(latestTag.dropFirst()) : latestTag

        let installedVersion = installations
            .compactMap(\.cliVersion)
            .sorted()
            .last

        if let installed = installedVersion {
            if installed.compare(latestVersion, options: .numeric) == .orderedAscending {
                availableCLIUpdate = latestTag
            }
        } else if !installations.isEmpty {
            availableCLIUpdate = latestTag
        }
    }

    @MainActor
    func dismissCLIUpdate() {
        availableCLIUpdate = nil
        evaluateReviewPromptEligibility()
    }

    // MARK: - Review Prompt

    @MainActor
    func evaluateReviewPromptEligibility() {
        guard isLoggedIn,
              !sessions.isEmpty,
              availableCLIUpdate == nil,
              ReviewPromptState.isEligibleForPrompt else {
            return
        }

        ReviewPromptState.recordPromptShown()
        shouldShowReviewPrompt = true
    }

    @MainActor
    func recordPositiveReviewIntent() async {
        ReviewPromptState.recordPositiveResponse()
        shouldShowReviewPrompt = false
        await submitReviewFeedback(kind: "review_positive", message: nil)
    }

    @MainActor
    func recordNegativeReviewIntent() {
        ReviewPromptState.recordNegativeResponse()
        shouldShowReviewPrompt = false
    }

    @MainActor
    func submitNegativeReviewFeedback(_ message: String) async {
        ReviewPromptState.recordFeedbackSubmitted()
        await submitReviewFeedback(kind: "review_negative", message: message)
    }

    private func submitReviewFeedback(kind: String, message: String?) async {
        guard let tokens = AuthTokens.stored else { return }

        do {
            do {
                try await SupabaseService.shared.submitFeedback(
                    token: tokens.accessToken,
                    kind: kind,
                    message: message,
                    appVersion: ReviewPromptState.appVersion
                )
            } catch SupabaseError.http(401, _) {
                let refreshed = try await SupabaseService.shared.refreshTokens(tokens.refreshToken)
                refreshed.persist()
                try await SupabaseService.shared.submitFeedback(
                    token: refreshed.accessToken,
                    kind: kind,
                    message: message,
                    appVersion: ReviewPromptState.appVersion
                )
            }
        } catch {
            print("AppModel: submit feedback error – \(error)")
        }
    }

    // MARK: - Auth

    func didSignIn() {
        isLoggedIn = true
        Task { await fetchSessions() }
    }

    func signOut() {
        AuthTokens.clear()
        isLoggedIn = false
        sessions = []
        installations = []
        selectedSession = nil
    }

    @MainActor
    func deleteAccount() async throws {
        guard let tokens = AuthTokens.stored else { throw SupabaseError.notLoggedIn }

        do {
            try await SupabaseService.shared.deleteCurrentUser(token: tokens.accessToken)
        } catch SupabaseError.http(401, _) {
            let refreshed = try await SupabaseService.shared.refreshTokens(tokens.refreshToken)
            refreshed.persist()
            try await SupabaseService.shared.deleteCurrentUser(token: refreshed.accessToken)
        }

        signOut()
    }

    // MARK: - Fetch

    @MainActor
    func fetchSessions() async {
        guard let tokens = AuthTokens.stored else { return }
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        do {
            do {
                try await loadAll(token: tokens.accessToken)
            } catch SupabaseError.http(401, _) {
                let refreshed = try await SupabaseService.shared.refreshTokens(tokens.refreshToken)
                refreshed.persist()
                try await loadAll(token: refreshed.accessToken)
            }
        } catch {
            // Keep whatever we have; don't blank the screen on transient errors
            print("AppModel: fetchSessions error – \(error)")
        }
    }

    @MainActor
    private func loadAll(token: String) async throws {
        async let s = SupabaseService.shared.fetchSessions(token: token)
        async let i = SupabaseService.shared.fetchInstallations(token: token)
        let (sList, iList) = try await (s, i)
        sessions = sList
        installations = iList

        // Leaderboard is optional — don't block sessions on it.
        do {
            leaderboard = try await SupabaseService.shared.fetchLeaderboard(token: token)
        } catch {
            print("AppModel: leaderboard unavailable – \(error)")
            leaderboard = []
        }

        // Check if CLI needs an update (non-blocking).
        Task {
            await checkForCLIUpdate()
            evaluateReviewPromptEligibility()
        }
    }
}

private enum ReviewPromptState {
    private static let appOpenCountKey = "reviewPrompt.appOpenCount"
    private static let lastPromptedAtKey = "reviewPrompt.lastPromptedAt"
    private static let lastPromptedAppVersionKey = "reviewPrompt.lastPromptedAppVersion"
    private static let lastResponseKey = "reviewPrompt.lastResponse"
    private static let positiveCountKey = "reviewPrompt.positiveCount"
    private static let negativeCountKey = "reviewPrompt.negativeCount"
    private static let feedbackCountKey = "reviewPrompt.feedbackCount"

    private static let day: TimeInterval = 24 * 60 * 60

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static func recordAppOpen() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: appOpenCountKey) + 1, forKey: appOpenCountKey)
    }

    static var isEligibleForPrompt: Bool {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: appOpenCountKey) >= 2 else { return false }
        guard defaults.string(forKey: lastPromptedAppVersionKey) != appVersion else { return false }

        let lastPromptedAt = defaults.double(forKey: lastPromptedAtKey)
        guard lastPromptedAt > 0 else { return true }

        let lastResponse = defaults.string(forKey: lastResponseKey)
        let waitDays: TimeInterval
        switch lastResponse {
        case "positive":
            waitDays = 120
        case "negative_feedback":
            waitDays = 60
        case "negative":
            waitDays = 30
        default:
            waitDays = 30
        }

        return Date().timeIntervalSince1970 - lastPromptedAt >= waitDays * day
    }

    static func recordPromptShown() {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: lastPromptedAtKey)
        defaults.set(appVersion, forKey: lastPromptedAppVersionKey)
    }

    static func recordPositiveResponse() {
        let defaults = UserDefaults.standard
        defaults.set("positive", forKey: lastResponseKey)
        defaults.set(defaults.integer(forKey: positiveCountKey) + 1, forKey: positiveCountKey)
    }

    static func recordNegativeResponse() {
        let defaults = UserDefaults.standard
        defaults.set("negative", forKey: lastResponseKey)
        defaults.set(defaults.integer(forKey: negativeCountKey) + 1, forKey: negativeCountKey)
    }

    static func recordFeedbackSubmitted() {
        let defaults = UserDefaults.standard
        defaults.set("negative_feedback", forKey: lastResponseKey)
        defaults.set(defaults.integer(forKey: feedbackCountKey) + 1, forKey: feedbackCountKey)
    }
}
