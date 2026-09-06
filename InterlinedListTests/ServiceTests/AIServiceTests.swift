import XCTest
@testable import InterlinedList

@MainActor
final class AIServiceTests: XCTestCase {
    var session: MockURLSession!
    var sut: AIService!

    private static let subscriberStatus = #"""
    {"subscriber":true,"providers":["anthropic"],
     "defaultModels":{"anthropic":"claude-sonnet-5"},
     "quota":{"usedToday":2,"dailyLimit":50,"remaining":48}}
    """#

    private static let freeStatus = #"""
    {"subscriber":false,"providers":[],"defaultModels":{},
     "quota":{"usedToday":0,"dailyLimit":50,"remaining":50}}
    """#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        let api = APIClient(session: session)
        api.setBearerToken("tok")
        sut = AIService(api: api)
    }

    private func user(subscriber: Bool) -> User {
        User(
            id: "u1", email: "a@b.co", username: "u", displayName: nil, avatar: nil,
            bio: nil, theme: nil, emailVerified: true, createdAt: nil,
            maxMessageLength: 666, showAdvancedPostSettings: nil, defaultPubliclyVisible: nil,
            customerStatus: subscriber ? "subscriber:monthly" : "free"
        )
    }

    // MARK: - Gating

    func test_isAvailable_usesLocalSubscriberFlagBeforeStatusLoads() {
        XCTAssertTrue(sut.isAvailable(for: user(subscriber: true)))
        XCTAssertFalse(sut.isAvailable(for: user(subscriber: false)))
        XCTAssertFalse(sut.isAvailable(for: nil))
    }

    func test_isAvailable_loadedStatusSupersedesStaleLocalFlag() async {
        session.stub(json: Self.freeStatus)
        await sut.refreshStatus()
        XCTAssertFalse(sut.isAvailable(for: user(subscriber: true)))
    }

    func test_isAvailable_statusGrantsAccessWhenLocalUserLooksFree() async {
        session.stub(json: Self.subscriberStatus)
        await sut.refreshStatus()
        XCTAssertTrue(sut.isAvailable(for: user(subscriber: false)))
    }

    func test_loadStatusIfNeeded_fetchesOnceOnly() async {
        session.stub(json: Self.subscriberStatus)
        await sut.loadStatusIfNeeded()
        await sut.loadStatusIfNeeded()
        XCTAssertEqual(session.requestHistory.filter { $0.url?.path == "/api/ai/status" }.count, 1)
    }

    /// Composer, list builder and documents all ask on appear; one request serves
    /// them all rather than three racing.
    func test_concurrentStatusLoadsShareOneRequest() async {
        session.stub(json: Self.subscriberStatus)
        async let first: Void = sut.loadStatusIfNeeded()
        async let second: Void = sut.loadStatusIfNeeded()
        async let third: Void = sut.refreshStatus()
        _ = await (first, second, third)
        XCTAssertEqual(session.requestHistory.filter { $0.url?.path == "/api/ai/status" }.count, 1)
        XCTAssertEqual(sut.quota?.remaining, 48)
    }

    func test_refreshStatus_refetchesAfterAnEarlierLoadCompleted() async {
        session.stub(json: Self.subscriberStatus)
        await sut.loadStatusIfNeeded()
        await sut.refreshStatus()
        XCTAssertEqual(session.requestHistory.filter { $0.url?.path == "/api/ai/status" }.count, 2)
    }

    func test_refreshStatus_populatesQuotaAndAttribution() async {
        session.stub(json: Self.subscriberStatus)
        await sut.refreshStatus()
        XCTAssertEqual(sut.quota?.remaining, 48)
        XCTAssertEqual(sut.attribution, "Powered by Claude Sonnet 5")
    }

    /// A failed status read must not hide a control the user is entitled to.
    func test_refreshStatus_transportFailureKeepsAffordanceVisible() async {
        session.stub(json: #"{"error":"boom"}"#, statusCode: 500)
        await sut.refreshStatus()
        XCTAssertFalse(sut.isDisabledForSession)
        XCTAssertTrue(sut.isAvailable(for: user(subscriber: true)))
    }

    func test_refreshStatus_noProviderConfiguredRetiresAffordance() async {
        session.stub(json: #"{"error":"AI is not configured.","code":"no_provider_configured"}"#, statusCode: 409)
        await sut.refreshStatus()
        XCTAssertTrue(sut.isDisabledForSession)
        XCTAssertFalse(sut.isAvailable(for: user(subscriber: true)))
    }

    // MARK: - suggest / generate

    func test_suggest_returnsArtifactAndUpdatesQuota() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"tags","tags":["swift"]},"quota":{"usedToday":9,"dailyLimit":50}}
        """#)
        let artifact = try await sut.suggest(feature: .writingAssist, input: "x", context: .writingAssist(.tags))
        XCTAssertEqual(artifact, .tags(["swift"]))
        XCTAssertEqual(sut.quota?.usedToday, 9)
        XCTAssertEqual(sut.quota?.remaining, 41)
    }

    func test_generate_returnsCreatedAndUpdatesQuota() async throws {
        session.stub(json: #"{"created":{"listId":"l1"},"quota":{"usedToday":10,"dailyLimit":50}}"#)
        let created = try await sut.generate(
            feature: .poweredTemplate,
            artifact: .list(AIListArtifact(title: "T", description: nil, dsl: .object([:]), rows: nil))
        )
        XCTAssertEqual(created.listId, "l1")
        XCTAssertEqual(sut.quota?.usedToday, 10)
    }

    func test_suggest_subscriptionRequiredRetiresAffordanceForSession() async {
        session.stub(json: #"{"error":"…","code":"subscription_required"}"#, statusCode: 403)
        await XCTAssertThrowsErrorAsync(try await sut.suggest(feature: .writingAssist, input: "x"))
        XCTAssertTrue(sut.isDisabledForSession)
        XCTAssertFalse(sut.isAvailable(for: user(subscriber: true)))
    }

    func test_suggest_quotaExceededZeroesRemaining() async {
        session.stub(json: Self.subscriberStatus)
        await sut.refreshStatus()
        session.stub(json: #"{"error":"Daily limit reached.","code":"quota_exceeded"}"#, statusCode: 429)
        await XCTAssertThrowsErrorAsync(try await sut.suggest(feature: .writingAssist, input: "x"))
        XCTAssertEqual(sut.quota?.remaining, 0)
        XCTAssertTrue(sut.quota?.isExhausted == true)
        // A spent budget is not an entitlement failure — the control stays.
        XCTAssertFalse(sut.isDisabledForSession)
    }

    func test_suggest_retryableFailureLeavesAffordanceAlone() async {
        session.stub(json: #"{"error":"junk","code":"invalid_ai_output"}"#, statusCode: 422)
        await XCTAssertThrowsErrorAsync(try await sut.suggest(feature: .writingAssist, input: "x"))
        XCTAssertFalse(sut.isDisabledForSession)
    }

    func test_suggest_rateLimitedSurfacesRetryAfter() async {
        session.stub(
            json: #"{"error":"Rate limited.","code":"rate_limited"}"#,
            statusCode: 429,
            headers: ["Retry-After": "30"]
        )
        do {
            _ = try await sut.suggest(feature: .writingAssist, input: "x")
            XCTFail("expected a failure")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 30))
        } catch {
            XCTFail("expected AIServiceError, got \(error)")
        }
    }
}

// MARK: - Async throw assertion

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {
        // Expected.
    }
}
