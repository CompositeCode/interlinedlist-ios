import XCTest
@testable import InterlinedList

/// Health resolution for all five providers, including the failure case.
final class IdentityHealthTests: XCTestCase {

    private func identity(_ provider: String, id: String = "id-1") -> APIClient.LinkedIdentity {
        APIClient.LinkedIdentity(
            id: id,
            provider: provider,
            providerUsername: "someone",
            createdAt: nil
        )
    }

    // MARK: all five report a status when configured

    func test_allFiveProviders_configured_readAsConnected() {
        let snapshot = IdentityStatusSnapshot(
            linkedin: .configured,
            twitter: .configured,
            bluesky: .configured,
            github: .configured,
            mastodon: ["techhub.social": .configured]
        )
        for provider in ["linkedin", "twitter", "bluesky", "github", "mastodon:techhub.social"] {
            XCTAssertEqual(snapshot.health(for: identity(provider)), .connected,
                           "\(provider) should read as connected")
        }
    }

    // MARK: the failure case — never a downgrade

    func test_failedStatusCall_degradesToUnknown_forEveryProvider() {
        let snapshot = IdentityStatusSnapshot(
            linkedin: .failed(unauthorized: false),
            twitter: .failed(unauthorized: false),
            bluesky: .failed(unauthorized: false),
            github: .failed(unauthorized: false),
            mastodon: ["techhub.social": .failed(unauthorized: false)]
        )
        for provider in ["linkedin", "twitter", "bluesky", "github", "mastodon:techhub.social"] {
            let health = snapshot.health(for: identity(provider))
            guard case .unknown = health else {
                return XCTFail("\(provider) failure should be unknown, got \(health)")
            }
            XCTAssertFalse(health.isStale, "\(provider) failure must not read as stale")
        }
    }

    /// The default snapshot is what a view holds before any call lands, and what it
    /// keeps if every call dies: unknown, never healthy and never disconnected.
    func test_defaultSnapshot_isUnknownNotConnected() {
        let snapshot = IdentityStatusSnapshot()
        for provider in ["linkedin", "twitter", "bluesky", "github", "mastodon:techhub.social"] {
            guard case .unknown = snapshot.health(for: identity(provider)) else {
                return XCTFail("\(provider) should default to unknown")
            }
        }
    }

    func test_failedCallDoesNotDowngradeAHealthyPeer() {
        let snapshot = IdentityStatusSnapshot(
            linkedin: .configured,
            twitter: .failed(unauthorized: false),
            bluesky: .configured,
            github: .failed(unauthorized: true),
            mastodon: [:]
        )
        XCTAssertEqual(snapshot.health(for: identity("linkedin")), .connected)
        XCTAssertEqual(snapshot.health(for: identity("bluesky")), .connected)
    }

    // MARK: notConfigured means different things per route kind

    /// Bluesky and Mastodon read per-user rows, so a `false` positively contradicts
    /// a listed identity — that is a genuine "needs reconnect".
    func test_perUserRoutes_notConfigured_needsReconnect() {
        let snapshot = IdentityStatusSnapshot(
            bluesky: .notConfigured,
            mastodon: ["techhub.social": .notConfigured]
        )
        XCTAssertTrue(snapshot.health(for: identity("bluesky")).isStale)
        XCTAssertTrue(snapshot.health(for: identity("mastodon:techhub.social")).isStale)
    }

    /// LinkedIn / Twitter / GitHub status reads no per-user data, so a `false` says
    /// the server lost its OAuth credentials. Reconnecting cannot fix that, so it
    /// must not be offered as a stale row.
    func test_serverConfigRoutes_notConfigured_isUnknownNotStale() {
        let snapshot = IdentityStatusSnapshot(
            linkedin: .notConfigured,
            twitter: .notConfigured,
            github: .notConfigured
        )
        for provider in ["linkedin", "twitter", "github"] {
            let health = snapshot.health(for: identity(provider))
            guard case .unknown = health else {
                return XCTFail("\(provider) should be unknown, got \(health)")
            }
            XCTAssertFalse(health.isStale, "\(provider) must not offer reconnect")
        }
    }

    // MARK: mastodon is per-instance

    func test_mastodon_resolvesPerInstance() {
        let snapshot = IdentityStatusSnapshot(
            mastodon: ["techhub.social": .configured, "mastodon.social": .notConfigured]
        )
        XCTAssertEqual(snapshot.health(for: identity("mastodon:techhub.social")), .connected)
        XCTAssertTrue(snapshot.health(for: identity("mastodon:mastodon.social")).isStale)
    }

    func test_mastodon_instanceWithNoStatusIsUnknown() {
        let snapshot = IdentityStatusSnapshot(mastodon: ["techhub.social": .configured])
        guard case .unknown = snapshot.health(for: identity("mastodon:other.example")) else {
            return XCTFail("an unchecked instance should be unknown")
        }
    }

    func test_bareMastodonProviderWithNoInstanceIsUnknown() {
        let snapshot = IdentityStatusSnapshot(mastodon: ["techhub.social": .configured])
        guard case .unknown = snapshot.health(for: identity("mastodon")) else {
            return XCTFail("mastodon with no instance suffix should be unknown")
        }
    }

    func test_unrecognisedProviderIsUnknown() {
        let snapshot = IdentityStatusSnapshot(linkedin: .configured)
        guard case .unknown = snapshot.health(for: identity("someothernetwork")) else {
            return XCTFail("an unknown provider should be unknown")
        }
    }

    // MARK: 401 surfacing

    func test_sawUnauthorized_onlyWhenA401Happened() {
        XCTAssertFalse(IdentityStatusSnapshot(linkedin: .configured, bluesky: .notConfigured).sawUnauthorized)
        XCTAssertTrue(IdentityStatusSnapshot(bluesky: .failed(unauthorized: true)).sawUnauthorized)
        XCTAssertTrue(IdentityStatusSnapshot(mastodon: ["a.example": .failed(unauthorized: true)]).sawUnauthorized)
    }

    // MARK: provider parsing

    func test_providerInstance_parsing() {
        XCTAssertEqual(identity("mastodon:techhub.social").providerInstance, "techhub.social")
        XCTAssertNil(identity("mastodon").providerInstance)
        XCTAssertNil(identity("mastodon:").providerInstance)
        XCTAssertEqual(identity("mastodon:techhub.social").providerType, "mastodon")
    }

    func test_statusKind_perProvider() {
        XCTAssertEqual(OAuthProvider.linkedin.statusKind, .serverConfiguration)
        XCTAssertEqual(OAuthProvider.twitter.statusKind, .serverConfiguration)
        XCTAssertEqual(OAuthProvider.github.statusKind, .serverConfiguration)
        XCTAssertEqual(OAuthProvider.bluesky.statusKind, .userIdentityRow)
        XCTAssertEqual(OAuthProvider.mastodon.statusKind, .userIdentityRow)
    }
}
