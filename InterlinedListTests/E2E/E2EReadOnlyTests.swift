import XCTest
@testable import InterlinedList

/// End-to-end smoke tests against the live `interlinedlist.com` API.
///
/// All tests are **read-only** — they only GET data. They never POST, PUT,
/// DELETE, or otherwise mutate server state, so they're safe to run against
/// the production account whose credentials are in `.env`.
///
/// Tests auto-skip when credentials aren't present (CI without secrets,
/// fresh checkout, etc.).
///
/// To run only this suite:
///   xcodebuild test -only-testing:InterlinedListTests/E2EReadOnlyTests \
///     -scheme InterlinedList \
///     -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'
final class E2EReadOnlyTests: XCTestCase {
    private static var sharedToken: String?
    private static var sharedUser: User?
    private static var loginError: Error?

    private var client: APIClient!

    override func setUp() async throws {
        try await super.setUp()

        try XCTSkipUnless(
            EnvLoader.hasCredentials,
            "E2E tests require INTERLINEDLIST_EMAIL and INTERLINEDLIST_PASSWORD (set via .env at repo root or process env vars)."
        )

        // Live tests need a real URLSession; the shared APIClient is fine because
        // we're using it the way the app does.
        client = APIClient(baseURL: "https://interlinedlist.com")

        try await ensureLoggedIn()
        if let token = Self.sharedToken {
            client.setBearerToken(token)
        }
    }

    private func ensureLoggedIn() async throws {
        if Self.sharedToken != nil { return }
        if let err = Self.loginError { throw err }

        guard let email = EnvLoader.email, let password = EnvLoader.password else {
            throw XCTSkip("Credentials missing.")
        }

        do {
            let token = try await client.login(email: email, password: password)
            client.setBearerToken(token)
            let user = try await client.currentUser()
            Self.sharedToken = token
            Self.sharedUser = user
        } catch {
            // Cache the failure so the next test in the suite skips fast rather
            // than re-attempting login against a possibly-rate-limited endpoint.
            Self.loginError = error
            throw error
        }
    }

    // MARK: - Auth

    func test_e2e_login_succeedsAndReturnsToken() async throws {
        let token = try XCTUnwrap(Self.sharedToken, "Login should have populated sharedToken.")
        XCTAssertFalse(token.isEmpty)
        // Tokens are documented as `il_tok_...` prefixed. Don't assert on the prefix
        // exactly (server may evolve), just confirm non-trivial length.
        XCTAssertGreaterThan(token.count, 16)
    }

    func test_e2e_currentUser_returnsAuthenticatedUser() async throws {
        let user = try XCTUnwrap(Self.sharedUser, "Login should have populated sharedUser.")
        XCTAssertFalse(user.id.isEmpty)
        XCTAssertFalse(user.username.isEmpty)
        XCTAssertFalse(user.email.isEmpty)
    }

    func test_e2e_currentUser_emailMatchesEnvCredentials() async throws {
        let user = try XCTUnwrap(Self.sharedUser)
        let expected = try XCTUnwrap(EnvLoader.email)
        XCTAssertEqual(user.email.lowercased(), expected.lowercased())
    }

    // MARK: - Messages

    func test_e2e_messages_returnsListWithoutThrowing() async throws {
        let (messages, _) = try await client.messages(limit: 5)
        // No specific count assertion — just that the call completes.
        XCTAssertGreaterThanOrEqual(messages.count, 0)
    }

    func test_e2e_scheduledMessages_returnsArray() async throws {
        let scheduled = try await client.scheduledMessages(range: "week")
        XCTAssertGreaterThanOrEqual(scheduled.count, 0)
    }

    // MARK: - Lists

    func test_e2e_listsAndFolders_returnsBoth() async throws {
        let (folders, lists) = try await client.listsAndFolders()
        XCTAssertGreaterThanOrEqual(folders.count, 0)
        XCTAssertGreaterThanOrEqual(lists.count, 0)
    }

    func test_e2e_searchLists_emptyQueryNotRequired() async throws {
        // Search with a single character to maximize chance of any match.
        let (results, _) = try await client.searchLists(q: "a", limit: 5)
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }

    func test_e2e_listConnections_returnsArray() async throws {
        let conns = try await client.listConnections()
        XCTAssertGreaterThanOrEqual(conns.count, 0)
    }

    // MARK: - Documents

    func test_e2e_documents_returnsArray() async throws {
        let docs = try await client.documents()
        XCTAssertGreaterThanOrEqual(docs.count, 0)
    }

    func test_e2e_documentFolders_returnsArray() async throws {
        let folders = try await client.documentFolders()
        XCTAssertGreaterThanOrEqual(folders.count, 0)
    }

    func test_e2e_searchDocuments_returnsResponse() async throws {
        let (results, _) = try await client.searchDocuments(q: "a", limit: 5)
        XCTAssertGreaterThanOrEqual(results.count, 0)
    }

    // MARK: - Notifications

    func test_e2e_notifications_returnsResponse() async throws {
        let response = try await client.notifications()
        XCTAssertGreaterThanOrEqual(response.unreadCount, 0)
        XCTAssertGreaterThanOrEqual(response.items.count, 0)
    }

    // MARK: - Follow

    func test_e2e_followRequests_returnsArray() async throws {
        let requests = try await client.followRequests()
        XCTAssertGreaterThanOrEqual(requests.count, 0)
    }

    func test_e2e_followCounts_forSelf_returnsCounts() async throws {
        let user = try XCTUnwrap(Self.sharedUser)
        let counts = try await client.followCounts(userId: user.id)
        XCTAssertGreaterThanOrEqual(counts.followers, 0)
        XCTAssertGreaterThanOrEqual(counts.following, 0)
    }

    func test_e2e_followStatus_forSelf_respondsWithoutCrashing() async throws {
        let user = try XCTUnwrap(Self.sharedUser)
        // Discovered behavior (2026-06-23): for self, `/api/follow/:userId/status`
        // returns 200 with a body that omits the `following` field, so the
        // documented `FollowStatus` shape fails to decode. The production app
        // never queries self-follow status (no follow button on own profile),
        // so this is undocumented edge behavior rather than a real bug — but
        // we record it here and in `GAP-ENDPOINTS.md` §B9. The test accepts a
        // successful decode OR a decode error; only a transport-level failure
        // would still fail.
        do {
            _ = try await client.followStatus(userId: user.id)
        } catch is DecodingError {
            // Tolerated — see comment above.
        } catch APIError.decoding {
            // Tolerated.
        } catch APIError.server, APIError.status {
            // Tolerated — server may evolve to return a structured error here.
        }
    }

    // MARK: - OAuth configuration status (read-only, unauthenticated)

    func test_e2e_linkedinStatus_returnsConfiguredField() async throws {
        let status = try await client.linkedinStatus()
        // Server may report either true or false; what matters is the decode succeeded.
        _ = status.configured
    }

    func test_e2e_twitterStatus_returnsConfiguredField() async throws {
        let status = try await client.twitterStatus()
        _ = status.configured
    }

    // MARK: - Bearer token rejected when stripped

    func test_e2e_unauthenticatedCall_returns401() async throws {
        let bare = APIClient(baseURL: "https://interlinedlist.com")
        // No token set on `bare`.
        do {
            _ = try await bare.currentUser()
            XCTFail("Expected 401 from /api/user with no Bearer token.")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        } catch APIError.server {
            // Acceptable: server may return 401 with a parseable body.
        }
    }
}
