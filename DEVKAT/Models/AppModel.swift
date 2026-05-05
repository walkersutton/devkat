import Foundation
import Observation
import UIKit

@Observable
final class AppModel {
    var selectedSession: Session?
    var sessions: [Session] = []
    var isLoggedIn: Bool = AuthTokens.stored != nil
    var isLoadingSessions = false

    init() {
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

    // MARK: - Auth

    func didSignIn() {
        isLoggedIn = true
        Task { await fetchSessions() }
    }

    func signOut() {
        AuthTokens.clear()
        isLoggedIn = false
        sessions = []
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
            var token = tokens.accessToken
            // Try fetch; if 401 refresh and retry once
            do {
                sessions = try await SupabaseService.shared.fetchSessions(token: token)
            } catch SupabaseError.http(401, _) {
                let refreshed = try await SupabaseService.shared.refreshTokens(tokens.refreshToken)
                refreshed.persist()
                token = refreshed.accessToken
                sessions = try await SupabaseService.shared.fetchSessions(token: token)
            }
        } catch {
            // Keep whatever we have; don't blank the screen on transient errors
            print("AppModel: fetchSessions error – \(error)")
        }
    }
}
