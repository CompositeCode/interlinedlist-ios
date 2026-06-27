//
//  OAuthCoordinator.swift
//  InterlinedList
//

import Foundation
import AuthenticationServices
import UIKit

enum OAuthProvider: String, CaseIterable {
    case github
    case mastodon
    case bluesky
    case linkedin
    case twitter

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .mastodon: return "Mastodon"
        case .bluesky: return "Bluesky"
        case .linkedin: return "LinkedIn"
        case .twitter: return "Twitter"
        }
    }

    var systemImageName: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .mastodon: return "bubble.left.and.bubble.right"
        case .bluesky: return "cloud"
        case .linkedin: return "briefcase"
        case .twitter: return "bird"
        }
    }

    /// Whether this provider's OAuth callback supports the native custom-scheme
    /// token handoff. GitHub's callback has no mobile branch — it sets a web
    /// session cookie and redirects to /dashboard, so it never returns
    /// `interlinedlist://oauth/callback?token=…` and can't complete inside
    /// `ASWebAuthenticationSession`. Hidden until the backend adds that branch.
    /// (Backend auth contract — Open Dependency #1.)
    var supportsNativeAuth: Bool { self != .github }
}

enum OAuthError: Error {
    case cancelled
    case missingToken
    case providerError(String)
    case noPresentationContext
}

/// Wraps `ASWebAuthenticationSession` and exchanges the deep-link callback for a Bearer token.
///
/// Flow: caller invokes `authenticate(provider:instance:link:)`, which launches the system
/// browser sheet pointing at `/api/auth/<provider>/authorize?redirect_uri=interlinedlist://oauth/callback`.
/// The server redirects back to the custom scheme with `?token=il_tok_...`; ASWebAuthenticationSession
/// captures that and returns the URL. We parse the token and return it.
@MainActor
final class OAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthCoordinator()

    private let baseURL: String
    private let callbackScheme = "interlinedlist"
    private var activeSession: ASWebAuthenticationSession?

    init(baseURL: String? = nil) {
        let defaultBase = "https://interlinedlist.com"
        let plistOverride = (Bundle.main.infoDictionary?["ILAPIBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (plistOverride?.isEmpty == false ? plistOverride : nil) ?? baseURL ?? defaultBase
        self.baseURL = resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
        super.init()
    }

    func authenticate(provider: OAuthProvider,
                      instance: String? = nil,
                      link: Bool = false) async throws -> String {
        guard let authURL = buildAuthorizeURL(provider: provider, instance: instance, link: link) else {
            throw OAuthError.providerError("Could not construct authorize URL.")
        }
        let callbackURL = try await startSession(url: authURL)
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            if let error = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value {
                throw OAuthError.providerError(error)
            }
            throw OAuthError.missingToken
        }
        return token
    }

    private func buildAuthorizeURL(provider: OAuthProvider, instance: String?, link: Bool) -> URL? {
        var components = URLComponents(string: baseURL + "/api/auth/\(provider.rawValue)/authorize")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://oauth/callback"),
        ]
        if provider == .mastodon, let instance, !instance.isEmpty {
            items.append(URLQueryItem(name: "instance", value: instance))
        }
        if link {
            items.append(URLQueryItem(name: "link", value: "true"))
        }
        components?.queryItems = items
        return components?.url
    }

    private func startSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OAuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.missingToken)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.noPresentationContext)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession invokes this synchronously on the main thread,
        // so assumeIsolated is safe and lets us call into UIKit's MainActor APIs.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
            return window ?? ASPresentationAnchor()
        }
    }
}
