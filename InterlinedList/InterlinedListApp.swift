//
//  InterlinedListApp.swift
//  InterlinedList
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct InterlinedListApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authState = AuthState()
    @StateObject private var store = AppDataStore()
    @StateObject private var router = AppRouter()

    init() {
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
                .environmentObject(store)
                .environmentObject(router)
                .onChange(of: authState.hasToken) { _, has in
                    if has {
                        PushService.shared.requestPermissionAndRegister()
                    } else {
                        PushService.shared.unregister()
                        store.reset()
                    }
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
        case .userProfile(let username):
            NavigationStack {
                UserProfileView(username: username)
            }
            .environmentObject(authState)
            .environmentObject(store)
        case .message(let id):
            MessageLinkView(messageId: id)
                .environmentObject(authState)
                .environmentObject(store)
        case .document(let id):
            DocumentLinkView(documentId: id)
                .environmentObject(authState)
        case .sharedDocument(let token):
            SharedDocumentView(token: token)
                .environmentObject(authState)
        case .verifyEmail, .verifyEmailChange:
            // These never present a sheet — they run an async side effect in
            // handleDeepLink and are never assigned to pendingDeepLink.
            EmptyView()
        }
    }

    // A2: Universal Links (a tapped https://interlinedlist.com link opening the app
    // directly). The Associated Domains entitlement (applinks:interlinedlist.com) is now
    // in place and `parse` already accepts https permalinks, so onOpenURL will route them
    // once the backend publishes apple-app-site-association and the Associated Domains
    // capability is enabled for the App ID / provisioning profile.
    private func handleDeepLink(_ url: URL) {
        // OAuth callbacks are captured by ASWebAuthenticationSession itself; the
        // app-level handler is a fallback for a torn-down session (safe to ignore).
        if url.scheme == "interlinedlist" && (url.host == "oauth" || url.path.hasPrefix("/oauth")) {
            return
        }
        // Token query items are read via AppDeepLink.parse but never logged — they're
        // sensitive bearer material handed off to KeychainService / OAuthCoordinator.
        guard let link = AppDeepLink.parse(url) else { return }
        switch link {
        case .verifyEmail(let token):
            Task { await verifyEmail(token: token) }
        case .verifyEmailChange(let token):
            Task { await verifyEmailChange(token: token) }
        case .resetPassword, .userProfile, .message, .document, .sharedDocument:
            router.pendingDeepLink = link
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

    private func configureNavigationBarAppearance() {
        let teal = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.047, green: 0.173, blue: 0.227, alpha: 1)
            : UIColor(red: 0.094, green: 0.282, blue: 0.376, alpha: 1) }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = teal
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        let back = UIBarButtonItemAppearance()
        back.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.backButtonAppearance = back
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
    }
}

enum AppDeepLink: Identifiable, Hashable {
    case resetPassword(token: String)
    case verifyEmail(token: String)
    case verifyEmailChange(token: String)
    case userProfile(username: String)
    case message(id: String)
    case document(id: String)
    case sharedDocument(token: String)

    var id: String {
        switch self {
        case .resetPassword(let token): return "reset:" + token
        case .verifyEmail(let token): return "verify:" + token
        case .verifyEmailChange(let token): return "verify-change:" + token
        case .userProfile(let username): return "profile:" + username
        case .message(let id): return "message:" + id
        case .document(let id): return "document:" + id
        case .sharedDocument(let token): return "shared-document:" + token
        }
    }

    /// Parses both the custom scheme (`interlinedlist://…`, where the target is the
    /// URL host or first path segment) and canonical web permalinks
    /// (`https://interlinedlist.com/…` / `https://www.interlinedlist.com/…`). Content
    /// links map to `.userProfile` / `.message`; auth links preserve their `?token`.
    /// Returns nil for unknown targets or web hosts other than interlinedlist.com.
    static func parse(_ url: URL) -> AppDeepLink? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased() ?? ""

        let target: String
        let segments: [String]
        if scheme == "interlinedlist" {
            let pathSegments = url.path.split(separator: "/").map(String.init)
            // The custom scheme puts the target in either the host (interlinedlist://user/bob)
            // or the first path segment (interlinedlist:///user/bob), so try the host first.
            if host.isEmpty {
                target = pathSegments.first ?? ""
                segments = Array(pathSegments.dropFirst())
            } else {
                target = host
                segments = pathSegments
            }
        } else if scheme == "https" || scheme == "http" {
            guard host == "interlinedlist.com" || host == "www.interlinedlist.com" else { return nil }
            let pathSegments = url.path.split(separator: "/").map(String.init)
            target = pathSegments.first ?? ""
            segments = Array(pathSegments.dropFirst())
        } else {
            return nil
        }

        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "token" })?.value

        switch target {
        case "user":
            guard let username = segments.first, !username.isEmpty else { return nil }
            return .userProfile(username: username)
        case "message":
            guard let id = segments.first, !id.isEmpty else { return nil }
            return .message(id: id)
        case "documents":
            // `/documents/shared/<token>` resolves a share link; `/documents/<id>`
            // opens a document permalink. (List permalinks are not routed: a bare
            // `/lists/<id>` carries no owner username, which the list-detail endpoint
            // requires — see the-gaps.md G10 follow-ons.)
            if segments.first == "shared" {
                guard segments.count >= 2, !segments[1].isEmpty else { return nil }
                return .sharedDocument(token: segments[1])
            }
            guard let id = segments.first, !id.isEmpty else { return nil }
            return .document(id: id)
        case "reset-password":
            guard let token, !token.isEmpty else { return nil }
            return .resetPassword(token: token)
        case "verify-email":
            guard let token, !token.isEmpty else { return nil }
            return .verifyEmail(token: token)
        case "verify-email-change":
            guard let token, !token.isEmpty else { return nil }
            return .verifyEmailChange(token: token)
        default:
            return nil
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var pendingDeepLink: AppDeepLink?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushService.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushService.shared.didFailToRegister(error: error)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            PushService.shared.handleForegroundNotification(notification, completionHandler: completionHandler)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            PushService.shared.handleNotificationResponse(response)
            completionHandler()
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            PushService.shared.clearBadge()
        }
    }
}
