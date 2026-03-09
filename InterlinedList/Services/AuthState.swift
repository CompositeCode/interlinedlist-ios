//
//  AuthState.swift
//  InterlinedList
//

import Foundation

@MainActor
final class AuthState: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isRestoring = true

    private let api = APIClient.shared

    init() {
        if let token = KeychainService.loadToken() {
            api.setBearerToken(token)
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
        } catch {
            logout()
        }
    }

    func login(email: String, password: String) async throws {
        let token = try await api.login(email: email, password: password)
        guard KeychainService.saveToken(token) else {
            throw APIError.server("Failed to save session")
        }
        api.setBearerToken(token)
        let currentUser = try await api.currentUser()
        user = currentUser
    }

    func register(email: String, username: String, password: String, displayName: String?) async throws {
        try await api.register(email: email, username: username, password: password, displayName: displayName)
        try await login(email: email, password: password)
    }

    func logout() {
        KeychainService.deleteToken()
        api.setBearerToken(nil)
        user = nil
    }

    func handleUnauthorized() {
        logout()
    }
}
