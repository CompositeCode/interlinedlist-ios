import XCTest
@testable import InterlinedList

final class APIClientAITests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func requestBody() throws -> [String: Any] {
        let data = try XCTUnwrap(session.lastRequest?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - aiStatus

    func test_aiStatus_sendsAuthenticatedGet() async throws {
        session.stub(json: #"{"subscriber":true,"providers":["anthropic"],"defaultModels":{},"quota":{"usedToday":0,"dailyLimit":50,"remaining":50}}"#)
        _ = try await sut.aiStatus()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/ai/status")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_aiStatus_decodesLiveShape() async throws {
        session.stub(json: #"""
        {"subscriber":true,"providers":["anthropic"],
         "defaultModels":{"anthropic":"claude-sonnet-5"},
         "quota":{"usedToday":3,"dailyLimit":50,"remaining":47}}
        """#)
        let status = try await sut.aiStatus()
        XCTAssertTrue(status.subscriber)
        XCTAssertEqual(status.providers, ["anthropic"])
        XCTAssertEqual(status.defaultModels?["anthropic"], "claude-sonnet-5")
        XCTAssertEqual(status.quota?.usedToday, 3)
        XCTAssertEqual(status.quota?.remaining, 47)
        XCTAssertEqual(status.attribution, "Powered by Claude Sonnet 5")
    }

    func test_aiStatus_freeUserDecodesWithoutSubscriber() async throws {
        session.stub(json: #"{"subscriber":false,"providers":[],"defaultModels":{},"quota":{"usedToday":0,"dailyLimit":50,"remaining":50}}"#)
        let status = try await sut.aiStatus()
        XCTAssertFalse(status.subscriber)
        XCTAssertNil(status.attribution)
    }

    // MARK: - aiSuggest

    func test_aiSuggest_postsFeatureInputAndContext() async throws {
        session.stub(json: #"{"ok":true,"feature":"writing_assist","artifact":{"kind":"message","content":"Tighter."}}"#)
        _ = try await sut.aiSuggest(
            feature: .writingAssist,
            input: "draft text",
            context: .writingAssist(.tighten)
        )
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/ai/suggest")
        let body = try requestBody()
        XCTAssertEqual(body["feature"] as? String, "writing_assist")
        XCTAssertEqual(body["input"] as? String, "draft text")
        let context = try XCTUnwrap(body["context"] as? [String: Any])
        XCTAssertEqual(context["action"] as? String, "tighten")
        // Unset context fields are omitted, not sent as null.
        XCTAssertNil(context["listId"])
        XCTAssertNil(context["mode"])
    }

    func test_aiSuggest_omitsContextWhenAbsent() async throws {
        session.stub(json: #"{"artifact":{"kind":"message","content":"x"}}"#)
        _ = try await sut.aiSuggest(feature: .writingAssist, input: "hello")
        XCTAssertNil(try requestBody()["context"])
    }

    func test_aiSuggest_decodesTagsArtifact() async throws {
        session.stub(json: #"{"ok":true,"artifact":{"kind":"tags","tags":["swift","ios"]}}"#)
        let suggestion = try await sut.aiSuggest(feature: .writingAssist, input: "x")
        XCTAssertEqual(suggestion.artifact, .tags(["swift", "ios"]))
    }

    func test_aiSuggest_decodesThreadArtifact() async throws {
        session.stub(json: #"{"artifact":{"kind":"thread","parts":["one","two"]}}"#)
        let suggestion = try await sut.aiSuggest(feature: .writingAssist, input: "x")
        XCTAssertEqual(suggestion.artifact, .thread(["one", "two"]))
    }

    func test_aiSuggest_decodesUsageAndQuota() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"message","content":"x"},
         "usage":{"inputTokens":12,"outputTokens":34,"model":"claude-sonnet-5"},
         "quota":{"usedToday":4,"dailyLimit":50}}
        """#)
        let suggestion = try await sut.aiSuggest(feature: .writingAssist, input: "x")
        XCTAssertEqual(suggestion.usage?.outputTokens, 34)
        XCTAssertEqual(suggestion.quota?.usedToday, 4)
        // /suggest omits `remaining`; it falls back to the difference.
        XCTAssertEqual(suggestion.quota?.remaining, 46)
    }

    func test_aiSuggest_decodesMessageSeriesArtifact() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"message_series","listTitle":"Launch week",
          "items":[{"order":1,"content":"first","crossPostTargets":["Bluesky"]},
                   {"order":2,"content":"second"}]}}
        """#)
        let suggestion = try await sut.aiSuggest(feature: .messageSeries, input: "x")
        guard case .messageSeries(let series) = suggestion.artifact else {
            return XCTFail("expected a message_series artifact")
        }
        XCTAssertEqual(series.listTitle, "Launch week")
        XCTAssertEqual(series.items.count, 2)
        XCTAssertEqual(series.items[0].crossPostTargets, ["Bluesky"])
        XCTAssertNil(series.items[1].crossPostTargets)
    }

    func test_aiSuggest_decodesDocSeriesArtifact() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"doc_series","folderTitle":"Series",
          "documents":[{"order":1,"title":"Part one","outline":["intro"]},
                       {"order":2,"title":"Part two","markdown":"# Two"}]}}
        """#)
        let suggestion = try await sut.aiSuggest(feature: .articleSeries, input: "x")
        guard case .docSeries(let series) = suggestion.artifact else {
            return XCTFail("expected a doc_series artifact")
        }
        XCTAssertEqual(series.folderTitle, "Series")
        XCTAssertEqual(series.documents[0].outline, ["intro"])
        XCTAssertEqual(series.documents[1].markdown, "# Two")
    }

    func test_aiSuggest_decodesDocumentArtifact() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"document","title":"Runbook","markdown":"# Runbook",
                     "outline":["Step 1"],"isPublic":false}}
        """#)
        let suggestion = try await sut.aiSuggest(feature: .poweredDocument, input: "x")
        XCTAssertEqual(
            suggestion.artifact,
            .document(AIDocumentArtifact(title: "Runbook", markdown: "# Runbook", outline: ["Step 1"], isPublic: false))
        )
    }

    func test_aiSuggest_messageSeriesSendsChannelLabels() async throws {
        session.stub(json: #"{"artifact":{"kind":"message_series","listTitle":"t","items":[]}}"#)
        _ = try await sut.aiSuggest(
            feature: .messageSeries,
            input: "a draft with plenty of words in it",
            context: .messageSeries(channels: ["Bluesky", "X/Twitter"])
        )
        let context = try XCTUnwrap(try requestBody()["context"] as? [String: Any])
        XCTAssertEqual(context["channels"] as? [String], ["Bluesky", "X/Twitter"])
    }

    // MARK: - Powered Template round-trip

    /// The DSL a Powered Template suggestion returns must reach `/generate`
    /// byte-faithfully: the server re-validates it, and a rewritten field key
    /// ("scheduled_at" → "scheduledAt") fails that check.
    func test_poweredTemplate_dslRoundTripsWithoutKeyMangling() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"list","title":"Talks","description":"Conference talks",
          "dsl":{"name":"Talks","fields":[
            {"key":"event_name","label":"Event","type":"text","required":true},
            {"key":"scheduled_at","label":"Date","type":"date"},
            {"key":"status","label":"Status","type":"select","options":["Draft","Confirmed"]}
          ]},
          "rows":[{"event_name":"Deploy Conf","scheduled_at":"2026-10-01","status":"Draft"}]}}
        """#)
        let suggestion = try await sut.aiSuggest(feature: .poweredTemplate, input: "conference talks")

        session.stub(json: #"{"ok":true,"created":{"listId":"list-1"}}"#)
        _ = try await sut.aiGenerate(feature: .poweredTemplate, artifact: suggestion.artifact)

        let body = try requestBody()
        let artifact = try XCTUnwrap(body["artifact"] as? [String: Any])
        XCTAssertEqual(artifact["kind"] as? String, "list")
        XCTAssertEqual(artifact["title"] as? String, "Talks")
        let dsl = try XCTUnwrap(artifact["dsl"] as? [String: Any])
        let fields = try XCTUnwrap(dsl["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.map { $0["key"] as? String }, ["event_name", "scheduled_at", "status"])
        XCTAssertEqual(fields[0]["required"] as? Bool, true)
        XCTAssertEqual(fields[2]["options"] as? [String], ["Draft", "Confirmed"])
        let rows = try XCTUnwrap(artifact["rows"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["scheduled_at"] as? String, "2026-10-01")
    }

    func test_poweredTemplate_exposesFieldLabelsForPreview() async throws {
        session.stub(json: #"""
        {"artifact":{"kind":"list","title":"Talks",
          "dsl":{"name":"Talks","fields":[{"key":"event","label":"Event","type":"text"},
                                          {"key":"venue","type":"text"}]}}}
        """#)
        let suggestion = try await sut.aiSuggest(feature: .poweredTemplate, input: "x")
        guard case .list(let list) = suggestion.artifact else { return XCTFail("expected a list artifact") }
        XCTAssertEqual(list.fieldLabels, ["Event", "venue"])
    }

    // MARK: - aiGenerate

    func test_aiGenerate_postsFeatureAndArtifact() async throws {
        session.stub(json: #"{"ok":true,"created":{"documentId":"doc-1"},"quota":{"usedToday":6,"dailyLimit":50}}"#)
        let result = try await sut.aiGenerate(
            feature: .poweredDocument,
            artifact: .document(AIDocumentArtifact(title: "T", markdown: "body", outline: nil, isPublic: nil))
        )
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/ai/generate")
        XCTAssertEqual(result.created.documentId, "doc-1")
        XCTAssertEqual(result.quota?.remaining, 44)
        let artifact = try XCTUnwrap(try requestBody()["artifact"] as? [String: Any])
        XCTAssertEqual(artifact["kind"] as? String, "document")
        XCTAssertEqual(artifact["markdown"] as? String, "body")
        // Optional artifact fields are omitted rather than sent as null.
        XCTAssertNil(artifact["outline"])
    }

    func test_aiGenerate_messageSeriesSendsCrossPostAndScheduleFlag() async throws {
        session.stub(json: #"""
        {"created":{"scheduledMessageIds":["m1","m2"],
                    "firstScheduledAt":"2026-09-05T18:00:00.000Z",
                    "lastScheduledAt":"2026-09-05T18:40:00.000Z"}}
        """#)
        let crossPost = AIComposerCrossPost(
            crossPostToBluesky: true,
            selectedMastodonIds: ["ident-1"],
            crossPostToTwitter: nil,
            crossPostToLinkedIn: true,
            selectedLinkedInTargets: [.orgPage(pageId: "page-9")],
            linkedInLinkAsFirstComment: true
        )
        let result = try await sut.aiGenerate(
            feature: .messageSeries,
            artifact: .messageSeries(AIMessageSeriesArtifact(
                listTitle: "Launch",
                items: [AIMessageSeriesItem(order: 1, content: "one", scheduledAt: nil, crossPostTargets: nil)]
            )),
            channels: ["Bluesky", "LinkedIn"],
            scheduleImmediately: true,
            crossPost: crossPost
        )
        XCTAssertEqual(result.created.scheduledMessageIds, ["m1", "m2"])
        XCTAssertEqual(result.created.firstScheduledAt, "2026-09-05T18:00:00.000Z")

        let body = try requestBody()
        XCTAssertEqual(body["scheduleImmediately"] as? Bool, true)
        XCTAssertEqual(body["channels"] as? [String], ["Bluesky", "LinkedIn"])
        let sent = try XCTUnwrap(body["crossPost"] as? [String: Any])
        XCTAssertEqual(sent["crossPostToBluesky"] as? Bool, true)
        XCTAssertEqual(sent["selectedMastodonIds"] as? [String], ["ident-1"])
        XCTAssertEqual(sent["linkedInLinkAsFirstComment"] as? Bool, true)
        XCTAssertNil(sent["crossPostToTwitter"])
        let targets = try XCTUnwrap(sent["selectedLinkedInTargets"] as? [[String: Any]])
        XCTAssertEqual(targets[0]["kind"] as? String, "orgPage")
        XCTAssertEqual(targets[0]["pageId"] as? String, "page-9")
    }

    func test_aiGenerate_omitsSeriesOnlyFieldsForOtherFeatures() async throws {
        session.stub(json: #"{"created":{"listId":"l1"}}"#)
        _ = try await sut.aiGenerate(
            feature: .poweredTemplate,
            artifact: .list(AIListArtifact(title: "T", description: nil, dsl: .object([:]), rows: nil))
        )
        let body = try requestBody()
        XCTAssertNil(body["crossPost"])
        XCTAssertNil(body["scheduleImmediately"])
        XCTAssertNil(body["channels"])
    }

    func test_aiGenerate_decodesArticleSeriesFolder() async throws {
        session.stub(json: #"{"created":{"folderId":"f1","documentIds":["d1","d2","d3"]}}"#)
        let result = try await sut.aiGenerate(
            feature: .articleSeries,
            artifact: .docSeries(AIDocSeriesArtifact(folderTitle: "S", documents: []))
        )
        XCTAssertEqual(result.created.folderId, "f1")
        XCTAssertEqual(result.created.documentIds?.count, 3)
    }

    // MARK: - Error mapping (§5.1 table)

    private func assertSuggestFails(
        status: Int,
        body: String,
        headers: [String: String]? = nil,
        expected: AIServiceError,
        line: UInt = #line
    ) async {
        session.stub(json: body, statusCode: status, headers: headers)
        do {
            _ = try await sut.aiSuggest(feature: .writingAssist, input: "x")
            XCTFail("expected a failure", line: line)
        } catch let error as AIServiceError {
            XCTAssertEqual(error, expected, line: line)
        } catch {
            XCTFail("expected AIServiceError, got \(error)", line: line)
        }
    }

    func test_error_subscriptionRequired() async {
        await assertSuggestFails(
            status: 403,
            body: #"{"error":"An InterlinedList subscription is required for AI features.","code":"subscription_required"}"#,
            expected: .subscriptionRequired
        )
    }

    /// The subscription gate's server copy steers toward a purchase; it must never
    /// reach the UI (App Store Guideline 3.1.1).
    func test_error_subscriptionRequired_neverSurfacesBackendUpsellCopy() {
        let message = AIServiceError.subscriptionRequired.userMessage
        XCTAssertFalse(message.lowercased().contains("subscription"))
        XCTAssertFalse(message.lowercased().contains("subscribe"))
        XCTAssertFalse(message.lowercased().contains("upgrade"))
        XCTAssertTrue(AIServiceError.subscriptionRequired.hidesAffordance)
    }

    func test_error_noProviderConfigured_isTransientOutage() async {
        await assertSuggestFails(
            status: 409,
            body: #"{"error":"AI is not configured on this server.","code":"no_provider_configured"}"#,
            expected: .unavailable
        )
        // Never a user-fixable state: no key-entry prompt, and the control retires.
        XCTAssertTrue(AIServiceError.unavailable.hidesAffordance)
        XCTAssertFalse(AIServiceError.unavailable.userMessage.lowercased().contains("key"))
    }

    func test_error_invalidAiOutput_isRetryable() async {
        await assertSuggestFails(
            status: 422,
            body: #"{"error":"Model did not return valid JSON.","code":"invalid_ai_output"}"#,
            expected: .invalidOutput
        )
        XCTAssertTrue(AIServiceError.invalidOutput.isRetryable)
    }

    func test_error_refused_mapsToInvalidOutput() async {
        await assertSuggestFails(
            status: 422,
            body: #"{"error":"Refused.","code":"refused"}"#,
            expected: .invalidOutput
        )
    }

    func test_error_invalidInput_keepsServerMessage() async {
        await assertSuggestFails(
            status: 422,
            body: #"{"error":"A basic amount of content is required (at least 10 words).","code":"invalid_input"}"#,
            expected: .invalidInput("A basic amount of content is required (at least 10 words).")
        )
    }

    func test_error_quotaExceeded() async {
        await assertSuggestFails(
            status: 429,
            body: #"{"error":"Daily limit reached.","code":"quota_exceeded"}"#,
            expected: .quotaExceeded
        )
        XCTAssertFalse(AIServiceError.quotaExceeded.isRetryable)
    }

    func test_error_rateLimited_honorsRetryAfterHeader() async {
        await assertSuggestFails(
            status: 429,
            body: #"{"error":"Rate limited. Retry in 42s.","code":"rate_limited"}"#,
            headers: ["Retry-After": "42"],
            expected: .rateLimited(retryAfter: 42)
        )
        XCTAssertTrue(AIServiceError.rateLimited(retryAfter: 42).userMessage.contains("42s"))
    }

    func test_error_rateLimited_withoutRetryAfterHeader() async {
        await assertSuggestFails(
            status: 429,
            body: #"{"error":"Rate limited.","code":"rate_limited"}"#,
            expected: .rateLimited(retryAfter: nil)
        )
    }

    func test_error_providerError() async {
        await assertSuggestFails(
            status: 502,
            body: #"{"error":"Upstream failure","code":"provider_error"}"#,
            expected: .providerError
        )
    }

    func test_error_internalErrorWithoutKnownCode_mapsByStatus() async {
        await assertSuggestFails(status: 500, body: #"{"error":"Internal error"}"#, expected: .providerError)
    }

    func test_error_unauthorized() async {
        await assertSuggestFails(
            status: 401,
            body: #"{"error":"Unauthorized","code":"unauthorized"}"#,
            expected: .unauthorized
        )
    }

    func test_error_malformedSuccessBody_isInvalidOutput() async {
        session.stub(json: #"{"artifact":{"kind":"nonsense"}}"#)
        do {
            _ = try await sut.aiSuggest(feature: .writingAssist, input: "x")
            XCTFail("expected a failure")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .invalidOutput)
        } catch {
            XCTFail("expected AIServiceError, got \(error)")
        }
    }

    func test_aiStatus_errorsAreTypedToo() async {
        session.stub(json: #"{"error":"Unauthorized","code":"unauthorized"}"#, statusCode: 401)
        do {
            _ = try await sut.aiStatus()
            XCTFail("expected a failure")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("expected AIServiceError, got \(error)")
        }
    }
}
