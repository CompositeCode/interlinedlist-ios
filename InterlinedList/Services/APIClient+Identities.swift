//
//  APIClient+Identities.swift
//  InterlinedList
//

import Foundation

/// The three OAuth status routes `APIClient.swift` didn't already cover
/// (`linkedinStatus()` / `twitterStatus()` live there).
///
/// **The five routes are not interchangeable, and none of them proves a token is
/// still good upstream.** Two different contracts hide behind the same `/status`
/// suffix:
///
/// - **LinkedIn, Twitter, GitHub** answer from server environment only
///   (`lib/integrations/connected-accounts-status.ts` — "nothing here reads
///   per-user data"). `configured` means the server holds OAuth app credentials
///   for the provider, so a `false` says the provider is unusable for *everyone*,
///   not that this user's connection went stale. GitHub's is **public** — no auth
///   check at all — while the other two simply ignore the Bearer we send.
/// - **Bluesky, Mastodon** are Bearer/session (`getCurrentUserOrSyncToken`) and
///   per-user, but only report whether a `LinkedIdentity` row exists for the
///   user. That is the same table `GET /api/user/identities` reads, so they
///   detect a row that vanished server-side — not a revoked token.
///
/// The backend *does* track real per-identity health (`LinkedIdentity.needsReconnect`,
/// flagged by `lib/twitter/token-refresh.ts` on a permanent auth failure, and
/// already surfaced by `getLinkedIdentitiesForUser`), but `GET /api/user/identities`
/// does not select it. Until it does, a token revoked upstream cannot be seen
/// from the app — see `IdentityHealth` for how far these routes let us go.
extension APIClient {

    /// `GET /api/auth/github/status` — public. `clientId` is not a secret (the
    /// client *secret* is never exposed); `manageOrgAccessUrl` is GitHub's
    /// authorized-app page, the only reliable place to grant org access to an
    /// already-authorized OAuth App.
    struct GitHubOAuthStatus: Decodable, Equatable {
        let configured: Bool
        let clientId: String?
        let manageOrgAccessUrl: String?
    }

    /// `GET /api/auth/{bluesky,mastodon}/status` — `configured` is "this user has a
    /// stored identity row for the provider", not "the stored token still works".
    struct ProviderLinkStatus: Decodable, Equatable {
        let configured: Bool
    }

    func githubStatus() async throws -> GitHubOAuthStatus {
        try await get("/api/auth/github/status")
    }

    func blueskyStatus() async throws -> ProviderLinkStatus {
        try await get("/api/auth/bluesky/status")
    }

    /// Mastodon is per-instance: the route **400s without `?instance=`** and looks
    /// up the identity stored as `mastodon:{instance}`, so each linked instance
    /// needs its own call.
    func mastodonStatus(instance: String) async throws -> ProviderLinkStatus {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "instance", value: instance)]
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            throw APIError.invalidURL
        }
        return try await get("/api/auth/mastodon/status?\(query)")
    }
}
