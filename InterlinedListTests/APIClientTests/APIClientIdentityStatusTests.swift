import XCTest
@testable import InterlinedList

/// The three status routes added in `APIClient+Identities.swift`.
///
/// Each call is stubbed on its own rather than fired together: `MockURLSession`
/// serves `enqueue` FIFO with no path matching, so the view's five concurrent
/// `async let` calls would consume the queue in nondeterministic order. The
/// aggregation those calls feed is covered by `IdentityHealthTests` instead.
final class APIClientIdentityStatusTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
    }

    override func tearDown() {
        sut = nil
        session = nil
        super.tearDown()
    }

    // MARK: githubStatus

    func test_githubStatus_sendsCorrectPathAndDecodes() async throws {
        session.stub(json: #"{"configured":true,"clientId":"Iv1.abc","manageOrgAccessUrl":"https://github.com/settings/connections/applications/Iv1.abc"}"#)
        let status = try await sut.githubStatus()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/github/status")
        XCTAssertTrue(status.configured)
        XCTAssertEqual(status.clientId, "Iv1.abc")
        XCTAssertEqual(status.manageOrgAccessUrl, "https://github.com/settings/connections/applications/Iv1.abc")
    }

    func test_githubStatus_notConfiguredDecodesNulls() async throws {
        session.stub(json: #"{"configured":false,"clientId":null,"manageOrgAccessUrl":null}"#)
        let status = try await sut.githubStatus()
        XCTAssertFalse(status.configured)
        XCTAssertNil(status.clientId)
        XCTAssertNil(status.manageOrgAccessUrl)
    }

    // MARK: blueskyStatus

    func test_blueskyStatus_sendsCorrectPathAndDecodes() async throws {
        session.stub(json: #"{"configured":true}"#)
        let status = try await sut.blueskyStatus()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/bluesky/status")
        XCTAssertTrue(status.configured)
    }

    func test_blueskyStatus_configuredFalse() async throws {
        session.stub(json: #"{"configured":false}"#)
        let status = try await sut.blueskyStatus()
        XCTAssertFalse(status.configured)
    }

    /// Bluesky is Bearer-authenticated, so a 401 has to reach the caller as
    /// `.status(401)` — the view re-validates rather than logging out.
    func test_blueskyStatus_401_throwsStatus401() async throws {
        session.stub(json: #"{"error":"Unauthorized"}"#, statusCode: 401)
        do {
            _ = try await sut.blueskyStatus()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: mastodonStatus

    func test_mastodonStatus_sendsInstanceQuery() async throws {
        session.stub(json: #"{"configured":true}"#)
        let status = try await sut.mastodonStatus(instance: "techhub.social")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/mastodon/status")
        XCTAssertEqual(session.lastRequest?.url?.query, "instance=techhub.social")
        XCTAssertTrue(status.configured)
    }

    func test_mastodonStatus_configuredFalse() async throws {
        session.stub(json: #"{"configured":false}"#)
        let status = try await sut.mastodonStatus(instance: "mastodon.social")
        XCTAssertFalse(status.configured)
    }

    /// An instance needing escaping must not be pasted raw into the query string —
    /// an unencoded `&` would split into a second query item and the route would
    /// see no instance at all (which it answers with a 400).
    func test_mastodonStatus_percentEncodesInstance() async throws {
        session.stub(json: #"{"configured":false}"#)
        _ = try await sut.mastodonStatus(instance: "a b&c")
        XCTAssertEqual(session.lastRequest?.url?.query, "instance=a%20b%26c")
    }

    func test_mastodonStatus_500_throws() async throws {
        session.stub(data: Data(), statusCode: 500)
        do {
            _ = try await sut.mastodonStatus(instance: "techhub.social")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 500)
        }
    }

    // MARK: existing two, for the five-provider set

    func test_linkedinStatus_stillReadsItsRoute() async throws {
        session.stub(json: #"{"configured":true,"redirectUri":"https://example.com/cb","orgScopesEnabled":false}"#)
        let status = try await sut.linkedinStatus()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/linkedin/status")
        XCTAssertTrue(status.configured)
    }

    func test_twitterStatus_stillReadsItsRoute() async throws {
        session.stub(json: #"{"configured":true,"redirectUri":"https://x/cb"}"#)
        let status = try await sut.twitterStatus()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/auth/twitter/status")
        XCTAssertTrue(status.configured)
    }
}
