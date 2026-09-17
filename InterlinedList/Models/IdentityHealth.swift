//
//  IdentityHealth.swift
//  InterlinedList
//

import Foundation

/// What a provider's `/status` route actually measures. The five routes look alike
/// and mean different things, so health has to be resolved per kind rather than by
/// treating every `configured: false` the same way (see `APIClient+Identities`).
enum ProviderStatusKind: Equatable {
    /// LinkedIn / Twitter / GitHub: server-side OAuth app credentials. Reads no
    /// per-user data, so it can never single out one user's stale connection.
    case serverConfiguration
    /// Bluesky / Mastodon: whether *this* user still has a stored identity row.
    case userIdentityRow
}

extension OAuthProvider {
    var statusKind: ProviderStatusKind {
        switch self {
        case .linkedin, .twitter, .github: return .serverConfiguration
        case .bluesky, .mastodon: return .userIdentityRow
        }
    }
}

/// The outcome of one status call.
///
/// `failed` is deliberately a case of its own rather than a `false`: a call that
/// could not be made proves nothing, and must never be read as "disconnected".
enum ProviderStatusOutcome: Equatable {
    case configured
    case notConfigured
    /// `unauthorized` marks a 401 so the view can re-validate the session through
    /// `authState.handleUnauthorized()`. A feature-endpoint 401 does **not** mean
    /// logged out — some routes only accept session cookies (CLAUDE.md).
    case failed(unauthorized: Bool)
}

/// Per-identity health, as far as the status routes can honestly report it.
enum IdentityHealth: Equatable {
    case connected
    /// Stronger than `connected`: the stored credential was exercised against the
    /// provider and came back working (`POST /api/user/identities/verify`). No
    /// `/status` route can produce this — none of them touches the token.
    case verified
    /// The provider positively contradicted a listed identity — the row it should
    /// have is gone, or the stored credential was rejected — so reconnecting is
    /// the repair.
    case needsReconnect(reason: String)
    /// Either the check failed, or the route can't speak to this identity at all.
    /// Never rendered as "disconnected".
    case unknown(reason: String)

    var isStale: Bool {
        if case .needsReconnect = self { return true }
        return false
    }
}

/// What `POST /api/user/identities/verify` answered for one identity.
///
/// Both cases are *answers*: the route loaded the stored credential and reported
/// on it. A check that could not be made throws instead of landing here, because
/// it proves nothing about the credential either way.
enum IdentityVerification: Equatable {
    /// `200 {"success":true}` — the credential still works upstream (and the
    /// backend stamped `lastVerifiedAt`).
    case verified
    case needsReconnect(IdentityVerificationFailure)
}

/// The two ways the verify route says "this connection is unusable".
enum IdentityVerificationFailure: Equatable {
    /// `400` — the provider rejected the stored credential (expired or revoked),
    /// or there is no token stored to check at all.
    case credentialRejected
    /// `404` — the account no longer has an identity row for this provider.
    case identityMissing
}

extension IdentityHealth {
    init(verification: IdentityVerification, providerName: String) {
        switch verification {
        case .verified:
            self = .verified
        case .needsReconnect(.credentialRejected):
            self = .needsReconnect(reason: "\(providerName) rejected the saved sign-in. Reconnect to keep posting.")
        case .needsReconnect(.identityMissing):
            self = .needsReconnect(reason: "\(providerName) is no longer connected to this account.")
        }
    }

    /// The check itself failed — no route, no session, no answer. Deliberately not
    /// `needsReconnect`: a dead check says nothing about the credential, and
    /// sending a user to re-authorize a working account is worse than saying nothing.
    static func uncheckable(providerName: String) -> IdentityHealth {
        .unknown(reason: "Couldn't run the check just now. Your \(providerName) connection is unchanged.")
    }
}

/// The five status outcomes gathered for one pass over `LinkedIdentitiesView`.
///
/// Every field defaults to `failed` so a snapshot that was never filled in reads
/// as *unknown* rather than as healthy or disconnected.
struct IdentityStatusSnapshot: Equatable {
    var linkedin: ProviderStatusOutcome = .failed(unauthorized: false)
    var twitter: ProviderStatusOutcome = .failed(unauthorized: false)
    var bluesky: ProviderStatusOutcome = .failed(unauthorized: false)
    var github: ProviderStatusOutcome = .failed(unauthorized: false)
    /// Mastodon is per-instance, keyed by the host out of `mastodon:{host}`.
    var mastodon: [String: ProviderStatusOutcome] = [:]

    var sawUnauthorized: Bool {
        ([linkedin, twitter, bluesky, github] + mastodon.values).contains(.failed(unauthorized: true))
    }

    func outcome(for identity: APIClient.LinkedIdentity) -> ProviderStatusOutcome {
        guard let provider = OAuthProvider(rawValue: identity.providerType) else {
            return .failed(unauthorized: false)
        }
        switch provider {
        case .linkedin: return linkedin
        case .twitter: return twitter
        case .bluesky: return bluesky
        case .github: return github
        case .mastodon:
            guard let instance = identity.providerInstance else {
                return .failed(unauthorized: false)
            }
            return mastodon[instance] ?? .failed(unauthorized: false)
        }
    }

    func health(for identity: APIClient.LinkedIdentity) -> IdentityHealth {
        guard let provider = OAuthProvider(rawValue: identity.providerType) else {
            return .unknown(reason: "No status check for this provider.")
        }
        switch outcome(for: identity) {
        case .configured:
            return .connected
        case .failed:
            return .unknown(reason: "Couldn't check this connection just now.")
        case .notConfigured:
            switch provider.statusKind {
            case .userIdentityRow:
                return .needsReconnect(
                    reason: "\(provider.displayName) no longer has this connection stored."
                )
            case .serverConfiguration:
                // The route answered about the *server*, not this user: reconnecting
                // can't fix missing OAuth credentials, so this is not "needs reconnect".
                return .unknown(
                    reason: "\(provider.displayName) sign-in is unavailable right now, so this connection can't be checked."
                )
            }
        }
    }
}

extension APIClient.LinkedIdentity {
    /// Instance host out of `mastodon:techhub.social`; `nil` when the provider
    /// string carries no suffix.
    var providerInstance: String? {
        guard let separator = provider.firstIndex(of: ":") else { return nil }
        let host = String(provider[provider.index(after: separator)...])
        return host.isEmpty ? nil : host
    }
}
