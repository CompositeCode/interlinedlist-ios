import XCTest
@testable import InterlinedList

final class APIClientMessagesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let messageJSON = #"{"id":"m1","content":"Hello","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
    private var messagesListJSON: String {
        #"{"messages":[\#(messageJSON)],"pagination":{"total":1,"limit":50,"offset":0,"has_more":false}}"#
    }

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: messages()

    func test_messages_sendsGetWithBearerToken() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_messages_pathContainsLimitAndOffset() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages(limit: 10, offset: 20)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=10"))
        XCTAssertTrue(url.contains("offset=20"))
    }

    func test_messages_onlyMine_appendsQueryParam() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages(onlyMine: true)
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("onlyMine=true"))
    }

    func test_messages_tag_appendsQueryParam() async throws {
        session.stub(json: messagesListJSON)
        _ = try await sut.messages(tag: "swift")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("tag=swift"))
    }

    func test_messages_decodesMessages() async throws {
        session.stub(json: messagesListJSON)
        let (msgs, _) = try await sut.messages()
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.id, "m1")
    }

    func test_messages_decodesPagination() async throws {
        session.stub(json: messagesListJSON)
        let (_, pagination) = try await sut.messages()
        XCTAssertEqual(pagination?.total, 1)
        XCTAssertEqual(pagination?.hasMore, false)
    }

    func test_messages_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.messages()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: postMessage()

    func test_postMessage_sendsPost() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "Hi")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages")
    }

    func test_postMessage_bodyIsCamelCase() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "Hi", publiclyVisible: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(json["publiclyVisible"], "Body must use camelCase key 'publiclyVisible'")
        XCTAssertNil(json["publicly_visible"], "Body must NOT use snake_case key")
    }

    func test_postMessage_crossPostBody_allProvidersCamelCase() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(
            content: "Hi",
            mastodonProviderIds: ["ident-1", "ident-2"],
            crossPostToBluesky: true,
            crossPostToLinkedIn: true,
            crossPostToTwitter: true
        )
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // All cross-post targets must ride as camelCase keys or the server drops them silently.
        XCTAssertEqual(json["crossPostToBluesky"] as? Bool, true)
        XCTAssertEqual(json["crossPostToLinkedIn"] as? Bool, true)
        XCTAssertEqual(json["crossPostToTwitter"] as? Bool, true)
        XCTAssertEqual(json["mastodonProviderIds"] as? [String], ["ident-1", "ident-2"])
        XCTAssertNil(json["cross_post_to_bluesky"], "Must not snake_case cross-post keys")
    }

    func test_postMessage_omitsCrossPostFields_whenNotRequested() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "plain post")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // Free users / no toggles → no cross-post keys leak into the request.
        XCTAssertNil(json["crossPostToBluesky"])
        XCTAssertNil(json["crossPostToLinkedIn"])
        XCTAssertNil(json["crossPostToTwitter"])
        XCTAssertNil(json["mastodonProviderIds"])
    }

    func test_postMessage_surfacesCrossPostUrlsFromCreatedMessage() async throws {
        // Real deployments echo destinations on the created message's `crossPostUrls`,
        // not the optional `crossPostResults` toast array.
        let response = """
        {"data":{"id":"m1","content":"hi","userId":"u1","createdAt":"t",
          "crossPostUrls":[
            {"platform":"mastodon","url":"https://techhub.social/@m/1","statusId":"1","instanceName":"techhub.social"},
            {"platform":"bluesky","url":"https://bsky.app/x","cid":"c1","uri":"at://u","instanceName":"Bluesky"}
          ]}}
        """
        session.stub(json: response, statusCode: 201)
        let result = try await sut.postMessage(content: "hi", crossPostToBluesky: true)
        let urls = try XCTUnwrap(result.message.crossPostUrls)
        XCTAssertEqual(urls.map(\.platform), ["mastodon", "bluesky"])
        XCTAssertEqual(urls.first?.destinationName, "techhub.social")
    }

    func test_postMessage_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.postMessage(content: "Hi")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_postMessage_withOrganizationId_sendsCamelCaseKeyInBody() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "Org post", organizationId: "org-42")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["organizationId"] as? String, "org-42",
                       "organizationId must appear as camelCase in the request body")
        XCTAssertNil(json["organization_id"], "snake_case key must not be sent")
    }

    func test_postMessage_withoutOrganizationId_omitsFieldFromBody() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.postMessage(content: "Plain post")
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["organizationId"], "organizationId must be absent when not provided")
        XCTAssertNil(json["organization_id"])
    }

    // MARK: editMessage()

    func test_editMessage_sendsPatchToCorrectPath() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.editMessage(id: "m1", content: "Updated", publiclyVisible: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1")
    }

    func test_editMessage_bodyUsesCamelCaseKeys() async throws {
        let wrapped = #"{"data":\#(messageJSON)}"#
        session.stub(json: wrapped)
        _ = try await sut.editMessage(id: "m1", content: "Updated", publiclyVisible: true)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["content"] as? String, "Updated")
        XCTAssertNotNil(json["publiclyVisible"], "Body must use camelCase key 'publiclyVisible'")
        XCTAssertNil(json["publicly_visible"], "Body must NOT use snake_case key")
    }

    // MARK: dig() / undig()

    func test_dig_sendsPostToDigPath() async throws {
        session.stub(json: #"{"digCount":1,"dugByMe":true}"#)
        let resp = try await sut.dig(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1/dig")
        XCTAssertEqual(resp.digCount, 1)
        XCTAssertTrue(resp.dugByMe)
    }

    func test_undig_sendsDeleteToDigPath() async throws {
        session.stub(json: #"{"digCount":0,"dugByMe":false}"#)
        let resp = try await sut.undig(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1/dig")
        XCTAssertEqual(resp.digCount, 0)
    }

    // MARK: replies()

    func test_replies_sendsGetToRepliesPath() async throws {
        session.stub(json: #"{"messages":[]}"#)
        _ = try await sut.replies(messageId: "m1")
        XCTAssertTrue(session.lastRequest?.url?.path.contains("/api/messages/m1/replies") == true)
    }

    // MARK: scheduledMessages()

    func test_scheduledMessages_sendsGetToScheduledPath() async throws {
        session.stub(json: #"{"messages":[]}"#)
        _ = try await sut.scheduledMessages()
        XCTAssertTrue(session.lastRequest?.url?.path.contains("/api/messages/scheduled") == true)
    }

    // MARK: deleteMessage()

    func test_deleteMessage_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.deleteMessage(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/messages/m1") == true)
    }

    func test_deleteMessage_403_throwsServerError() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            try await sut.deleteMessage(id: "m1")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertTrue(msg.lowercased().contains("own"))
        }
    }

    // MARK: refreshMessageMetadata()

    /// Every fixture below is transcribed from the route itself —
    /// `app/api/messages/[id]/metadata/route.ts` (`serialize({ links: … })` at :86
    /// and :105) — and from the entry shape its items are built with,
    /// `lib/messages/metadata-fetcher.ts` (`fetchMultipleLinkMetadata`, which also
    /// feeds `GET /api/link-metadata`). Do not re-derive them from the Swift type:
    /// the bug this covers (#104) shipped green because the old fixture was written
    /// to the decoder's assumption instead of to the wire.
    private let metadataSuccessJSON = #"""
    {"links":[{
      "url":"https://example.com/post",
      "platform":"other",
      "metadata":{
        "thumbnail":"https://example.com/og.png",
        "title":"Example Post",
        "description":"A description",
        "type":"link",
        "ogType":"article"
      },
      "fetchStatus":"success",
      "fetchedAt":"2026-09-16T12:00:00.000Z"
    }]}
    """#

    func test_refreshMessageMetadata_sendsPostToMetadataPath() async throws {
        session.stub(json: metadataSuccessJSON)
        _ = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1/metadata")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_refreshMessageMetadata_routeShape_decodesNonEmptyLinks() async throws {
        session.stub(json: metadataSuccessJSON)
        let links = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url, "https://example.com/post")
        XCTAssertEqual(links.first?.platform, "other")
        XCTAssertEqual(links.first?.fetchStatus, "success")
        XCTAssertEqual(links.first?.metadata?.title, "Example Post")
        XCTAssertEqual(links.first?.metadata?.description, "A description")
        XCTAssertEqual(links.first?.metadata?.thumbnail, "https://example.com/og.png")
        XCTAssertEqual(links.first?.metadata?.type, "link")
    }

    /// The pre-#104 shape: a `metadata` wrapper the route has never sent. It must
    /// now fail loudly rather than decode to an empty array, which is how the
    /// mismatch stayed invisible.
    func test_refreshMessageMetadata_legacyMetadataWrapper_throwsDecodingError() async throws {
        session.stub(json: #"{"message":"ok","metadata":{"links":[{"url":"https://x.com","title":"X","description":"d","image":"i"}]}}"#)
        do {
            _ = try await sut.refreshMessageMetadata(messageId: "m1")
            XCTFail("Expected a decoding failure for the wrapped shape")
        } catch is DecodingError {
            // expected
        }
    }

    /// Route :84-89 — content with no detectable link short-circuits to `{links:[]}`.
    func test_refreshMessageMetadata_noDetectedLinks_returnsEmpty() async throws {
        session.stub(json: #"{"links":[]}"#)
        let links = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertTrue(links.isEmpty)
    }

    /// `fetchMultipleLinkMetadata` emits `{url, platform, fetchStatus:"failed"}` with
    /// no `metadata` and no `fetchedAt` when a fetch throws or resolves to nothing —
    /// and the route persists exactly that on the message, so the item is kept.
    func test_refreshMessageMetadata_failedEntry_keepsUrlWithNilMetadata() async throws {
        session.stub(json: #"{"links":[{"url":"https://dead.example","platform":"other","fetchStatus":"failed"}]}"#)
        let links = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url, "https://dead.example")
        XCTAssertEqual(links.first?.fetchStatus, "failed")
        XCTAssertNil(links.first?.metadata)
    }

    /// Instagram entries carry `caption`/`derivedList` for the composer's
    /// paste-to-expand assist; the link card models neither, and neither may break
    /// the decode of the fields it does model.
    func test_refreshMessageMetadata_instagramExtras_decodeWithoutError() async throws {
        session.stub(json: #"""
        {"links":[{
          "url":"https://www.instagram.com/p/abc123/",
          "platform":"instagram",
          "metadata":{"thumbnail":"https://cdn.example/ig.jpg","title":"On Instagram","description":"caption text","type":"image"},
          "caption":"caption text - one - two",
          "derivedList":{"markdown":"- one","ordered":false,"itemCount":2},
          "fetchStatus":"success",
          "fetchedAt":"2026-09-16T12:00:00.000Z"
        }]}
        """#)
        let links = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertEqual(links.first?.platform, "instagram")
        XCTAssertEqual(links.first?.metadata?.type, "image")
        XCTAssertEqual(links.first?.metadata?.thumbnail, "https://cdn.example/ig.jpg")
    }

    func test_refreshMessageMetadata_multipleLinks_preservesRouteOrder() async throws {
        session.stub(json: #"""
        {"links":[
          {"url":"https://one.example","platform":"other","metadata":{"title":"One","type":"link"},"fetchStatus":"success"},
          {"url":"https://two.example","platform":"other","metadata":{"title":"Two","type":"link"},"fetchStatus":"success"}
        ]}
        """#)
        let links = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertEqual(links.map(\.url), ["https://one.example", "https://two.example"])
        XCTAssertEqual(links.map { $0.metadata?.title }, ["One", "Two"])
    }

    /// Route :65-67 — the POST is owner-only, so an unauthenticated refresh 401s.
    /// It stays a bare `.status(401)`: the publish path swallows it rather than
    /// treating it as a logout (CLAUDE.md).
    func test_refreshMessageMetadata_401_throwsStatus401() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.refreshMessageMetadata(messageId: "m1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
