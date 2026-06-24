//
//  InterlinedListApp.swift
//  InterlinedList
//

import SwiftUI

@main
struct InterlinedListApp: App {
    @StateObject private var authState = AuthState()
    @StateObject private var store = AppDataStore()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
                .environmentObject(store)
                .environmentObject(router)
                .onChange(of: authState.hasToken) { _, has in
                    if !has { store.reset() }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .sheet(item: $router.pendingDeepLink) { link in
                    deepLinkSheet(for: link)
                }
        }
    }

    @ViewBuilder
    private func deepLinkSheet(for link: AppDeepLink) -> some View {
        switch link {
        case .resetPassword(let token):
            ResetPasswordView(token: token)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "interlinedlist" else { return }
        // Token query items are read but never logged — they're sensitive bearer
        // material handed off to KeychainService / OAuthCoordinator.
        let host = url.host ?? ""
        let path = url.path
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = components?.queryItems?.first(where: { $0.name == "token" })?.value

        switch (host, path) {
        case ("reset-password", _), ("", "/reset-password"):
            if let token, !token.isEmpty {
                router.pendingDeepLink = .resetPassword(token: token)
            }
        case ("verify-email", _), ("", "/verify-email"):
            if let token, !token.isEmpty {
                Task { await verifyEmail(token: token) }
            }
        case ("verify-email-change", _), ("", "/verify-email-change"):
            if let token, !token.isEmpty {
                Task { await verifyEmailChange(token: token) }
            }
        case ("oauth", _):
            // ASWebAuthenticationSession captures the callback automatically; the
            // app-level handler is a fallback for when the session has been torn
            // down (rare; safe to ignore the token rather than re-exchange it).
            break
        default:
            break
        }
    }

    @MainActor
    private func verifyEmail(token: String) async {
        do {
            try await APIClient.shared.verifyEmail(token: token)
            await authState.refreshUser()
        } catch {
            // Surfacing this through router would require an alert path; skip
            // silently. The user will see emailVerified flip in the banner if it
            // succeeded.
        }
    }

    @MainActor
    private func verifyEmailChange(token: String) async {
        do {
            try await APIClient.shared.verifyEmailChange(token: token)
            await authState.refreshUser()
        } catch {
            // Same rationale as verifyEmail above.
        }
    }
}

enum AppDeepLink: Identifiable, Hashable {
    case resetPassword(token: String)

    var id: String {
        switch self {
        case .resetPassword(let token): return "reset:" + token
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var pendingDeepLink: AppDeepLink?
}
