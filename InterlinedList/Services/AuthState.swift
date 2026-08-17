//
//  AuthState.swift
//  InterlinedList
//

import Foundation

@MainActor
final class AuthState: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isRestoring = true
    @Published private(set) var hasToken: Bool = false
    /// Provider types (e.g. "github", "mastodon") linked to this account, or nil
    /// until first loaded. Populated lazily via `loadLinkedProvidersIfNeeded()`.
    @Published private(set) var linkedProviders: Set<String>?

    private let api = APIClient.shared

    init() {
        if let token = KeychainService.loadToken() {
            api.setBearerToken(token)
            hasToken = true
            Task { await validateSession() }
        } else {
            isRestoring = false
        }
    }

    var isLoggedIn: Bool {
        user != nil
    }

    func validateSession() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let currentUser = try await api.currentUser()
            user = currentUser
        } catch APIError.status(401) {
            // Session token is explicitly rejected — clear it.
            logout()
        } catch {
            // Network error, decode failure, server error — token may still be valid.
            // Keep the user logged in; individual views will surface their own errors.
            if user == nil {
                // No user was ever set this launch, so there's nothing to keep.
                logout()
            }
        }
    }

    func login(email: String, password: String) async throws {
        do {
            let token = try await api.login(email: email, password: password)
            guard KeychainService.saveToken(token) else {
                throw APIError.server("Failed to save session")
            }
            api.setBearerToken(token)
            hasToken = true
            do {
                let currentUser = try await api.currentUser()
                user = currentUser
            } catch APIError.status(401) {
                throw APIError.server("Session was created but the server rejected it. The server may need an update to support app login.")
            }
        } catch {
            throw error
        }
    }

    func register(email: String, username: String, password: String, displayName: String?) async throws {
        try await api.register(email: email, username: username, password: password, displayName: displayName)
        try await login(email: email, password: password)
    }

    func completeOAuthLogin(token: String) async throws {
        guard KeychainService.saveToken(token) else {
            throw APIError.server("Failed to save session")
        }
        api.setBearerToken(token)
        hasToken = true
        let currentUser = try await api.currentUser()
        user = currentUser
    }

    func refreshUser() async {
        do {
            user = try await api.currentUser()
        } catch APIError.status(401) {
            logout()
        } catch {
            // Keep current user state; transient failure.
        }
    }

    /// True once linked providers have been loaded and include GitHub. Returns
    /// false while unloaded, so callers should trigger `loadLinkedProvidersIfNeeded()`.
    var hasGitHubIdentity: Bool {
        linkedProviders?.contains("github") == true
    }

    /// Loads the account's linked provider types once (cached until logout).
    /// Failures leave `linkedProviders` unset so a later call can retry.
    func loadLinkedProvidersIfNeeded() async {
        guard linkedProviders == nil else { return }
        do {
            let identities = try await api.linkedIdentities()
            linkedProviders = Set(identities.map { $0.providerType })
        } catch {
            // Leave nil to allow retry; callers treat absence as "no known GitHub".
        }
    }

    func logout() {
        _ = KeychainService.deleteToken()
        api.setBearerToken(nil)
        user = nil
        hasToken = false
        linkedProviders = nil
    }

    func updateUser(_ updated: User) {
        user = updated
    }

    func handleUnauthorized() {
        // An endpoint returned 401, but that doesn't prove the session is dead —
        // some endpoints only accept session-cookie auth and will reject a valid Bearer token.
        // Re-validate against /api/user before deciding to log out.
        Task {
            do {
                let currentUser = try await api.currentUser()
                user = currentUser  // Session still valid; refresh user data.
            } catch APIError.status(401) {
                logout()  // /api/user itself rejected the token — genuinely expired.
            } catch {
                // Network error — token may still be valid; don't log out.
            }
        }
    }
}
