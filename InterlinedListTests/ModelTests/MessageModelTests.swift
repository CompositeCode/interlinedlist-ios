import XCTest
@testable import InterlinedList

final class MessageCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_requiredFields() throws {
        let json = #"{"id":"m1","content":"Hello","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.id, "m1")
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertEqual(msg.userId, "u1")
    }

    func test_decode_optionalFieldsAbsent() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertNil(msg.tags)
        XCTAssertNil(msg.imageUrls)
        XCTAssertNil(msg.videoUrls)
        XCTAssertNil(msg.digCount)
        XCTAssertNil(msg.dugByMe)
        XCTAssertNil(msg.parentId)
    }

    func test_decode_tagsArray() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z","tags":["swift","ios"]}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.tags, ["swift", "ios"])
    }

    func test_decode_digFields() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z","dig_count":5,"dug_by_me":true}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.digCount, 5)
        XCTAssertEqual(msg.dugByMe, true)
    }

    func test_authorDisplay_prefersDisplayName() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z","user":{"id":"u1","username":"alice","display_name":"Alice Smith","avatar":null}}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.authorDisplay, "Alice Smith")
    }

    func test_authorDisplay_fallsBackToUsername_whenDisplayNameEmpty() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z","user":{"id":"u1","username":"alice","display_name":"","avatar":null}}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.authorDisplay, "alice")
    }

    func test_authorDisplay_unknownWhenNoUser() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(msg.authorDisplay, "Unknown")
    }

    func test_hasPreviews_trueWhenImageUrls() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z","image_urls":["https://img.example.com/a.jpg"]}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertTrue(msg.hasPreviews)
    }

    func test_hasPreviews_falseWhenNoMedia() throws {
        let json = #"{"id":"m1","content":"Hi","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertFalse(msg.hasPreviews)
    }
}

/// Cross-post outcomes the live API echoes back on a published message under
/// `crossPostUrls`. Fixtures mirror real production payloads (Mastodon carries
/// `statusId`/`instanceUrl`; Bluesky carries `cid`/`uri`). Before the model had
/// this field the client silently dropped every cross-post result, so a
/// message that reached Mastodon and Bluesky looked like it went nowhere.
final class MessageCrossPostUrlTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// The server sends camelCase keys (`crossPostUrls`, `statusId`, `instanceUrl`);
    /// `convertFromSnakeCase` leaves already-camelCased keys untouched, so this is
    /// the exact wire shape.
    private let crossPostedMessageJSON = """
    {
      "id": "b9790651",
      "content": "hello world",
      "userId": "u1",
      "createdAt": "2026-06-16T16:24:41.517Z",
      "crossPostUrls": [
        {
          "url": "https://techhub.social/@messenger/116760712467163263",
          "platform": "mastodon",
          "statusId": "116760712467163263",
          "statusIds": ["116760712467163263"],
          "instanceUrl": "https://techhub.social",
          "instanceName": "techhub.social"
        },
        {
          "cid": "bafyreigc73ih62tjoiazh7fvcs3lojxgbnqrn6gkoghytptqkrou2pjdkq",
          "uri": "at://did:plc:zassnetq2zlougqaofypwrgu/app.bsky.feed.post/3mog7kr5ydr2k",
          "url": "https://bsky.app/profile/interlinedlist.bsky.social/post/3mog7kr5ydr2k",
          "uris": ["at://did:plc:zassnetq2zlougqaofypwrgu/app.bsky.feed.post/3mog7kr5ydr2k"],
          "platform": "bluesky",
          "instanceName": "Bluesky"
        }
      ]
    }
    """

    func test_decode_crossPostUrls_bothPlatforms() throws {
        let msg = try decoder.decode(Message.self, from: Data(crossPostedMessageJSON.utf8))
        let urls = try XCTUnwrap(msg.crossPostUrls)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.map(\.platform), ["mastodon", "bluesky"])
    }

    func test_decode_crossPostUrls_mastodonFields() throws {
        let msg = try decoder.decode(Message.self, from: Data(crossPostedMessageJSON.utf8))
        let mastodon = try XCTUnwrap(msg.crossPostUrls?.first { $0.platform == "mastodon" })
        XCTAssertEqual(mastodon.statusId, "116760712467163263")
        XCTAssertEqual(mastodon.instanceUrl, "https://techhub.social")
        XCTAssertEqual(mastodon.destinationName, "techhub.social")
        XCTAssertNil(mastodon.cid)
    }

    func test_decode_crossPostUrls_blueskyFields() throws {
        let msg = try decoder.decode(Message.self, from: Data(crossPostedMessageJSON.utf8))
        let bluesky = try XCTUnwrap(msg.crossPostUrls?.first { $0.platform == "bluesky" })
        XCTAssertEqual(bluesky.cid, "bafyreigc73ih62tjoiazh7fvcs3lojxgbnqrn6gkoghytptqkrou2pjdkq")
        XCTAssertEqual(bluesky.uri, "at://did:plc:zassnetq2zlougqaofypwrgu/app.bsky.feed.post/3mog7kr5ydr2k")
        XCTAssertEqual(bluesky.destinationName, "Bluesky")
        XCTAssertNil(bluesky.statusId)
    }

    func test_decode_crossPostUrls_absent_isNil() throws {
        let json = #"{"id":"m1","content":"Hi","userId":"u1","createdAt":"2024-01-01T00:00:00Z"}"#
        let msg = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertNil(msg.crossPostUrls)
    }

    func test_crossPostUrl_destinationName_fallsBackToPlatform_whenNoInstanceName() throws {
        let json = #"{"platform":"bluesky","url":"https://bsky.app/x","instanceName":null}"#
        let item = try decoder.decode(CrossPostUrl.self, from: Data(json.utf8))
        XCTAssertEqual(item.destinationName, "Bluesky")
    }

    // MARK: - CrossPostSummary.line (drives the "Message Posted" dialog)

    private func url(_ platform: String, instanceName: String?) -> CrossPostUrl {
        let name = instanceName.map { "\"\($0)\"" } ?? "null"
        let json = "{\"platform\":\"\(platform)\",\"url\":\"https://x/y\",\"instanceName\":\(name)}"
        return try! decoder.decode(CrossPostUrl.self, from: Data(json.utf8))
    }

    private func result(_ platform: String?, success: Bool?, error: String? = nil) -> CrossPostResult {
        let p = platform.map { "\"\($0)\"" } ?? "null"
        let s = success.map { "\($0)" } ?? "null"
        let e = error.map { "\"\($0)\"" } ?? "null"
        let json = "{\"platform\":\(p),\"success\":\(s),\"error\":\(e)}"
        return try! decoder.decode(CrossPostResult.self, from: Data(json.utf8))
    }

    func test_summary_usesDestinationNames_fromUrls() {
        let urls = [url("mastodon", instanceName: "techhub.social"), url("bluesky", instanceName: "Bluesky")]
        XCTAssertEqual(CrossPostSummary.line(urls: urls, results: []), "techhub.social ✓ · Bluesky ✓")
    }

    func test_summary_prefersUrls_evenWhenResultsHaveNilPlatform() {
        // The reported bug: results with nil platform used to render "Cross-post ✓".
        let urls = [url("linkedin", instanceName: "LinkedIn")]
        let results = [result(nil, success: true), result(nil, success: true)]
        XCTAssertEqual(CrossPostSummary.line(urls: urls, results: results), "LinkedIn ✓")
    }

    func test_summary_appendsFailuresFromResults() {
        let urls = [url("bluesky", instanceName: "Bluesky")]
        let results = [result("mastodon", success: false, error: "rate limited")]
        XCTAssertEqual(CrossPostSummary.line(urls: urls, results: results), "Bluesky ✓ · Mastodon ✗ (rate limited)")
    }

    func test_summary_fallsBackToResults_whenNoUrls() {
        let results = [result("bluesky", success: true), result("linkedin", success: false)]
        XCTAssertEqual(CrossPostSummary.line(urls: [], results: results), "Bluesky ✓ · Linkedin ✗")
    }

    func test_summary_isNil_whenNothingToShow() {
        XCTAssertNil(CrossPostSummary.line(urls: [], results: []))
    }
}

final class CreateMessageBodyEncodingTests: XCTestCase {
    // camelCaseEncoder is the plain JSONEncoder (no key strategy); keys are
    // already camelCase in the struct, so they survive encoding unchanged.
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private func encodedJSON(_ body: CreateMessageBody) throws -> [String: Any] {
        let data = try encoder.encode(body)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeBody(
        content: String = "Test",
        publiclyVisible: Bool? = nil,
        parentId: String? = nil,
        tags: [String]? = nil,
        scheduledAt: String? = nil,
        imageUrls: [String]? = nil,
        videoUrls: [String]? = nil,
        pushedMessageId: String? = nil,
        mastodonProviderIds: [String]? = nil,
        crossPostToBluesky: Bool? = nil,
        crossPostToLinkedIn: Bool? = nil,
        linkedInTargets: [LinkedInTarget]? = nil,
        linkedInLinkAsFirstComment: Bool? = nil,
        crossPostToTwitter: Bool? = nil,
        scheduledCrossPostConfig: ScheduledCrossPostConfig? = nil,
        organizationId: String? = nil
    ) -> CreateMessageBody {
        CreateMessageBody(
            content: content, publiclyVisible: publiclyVisible, parentId: parentId,
            tags: tags, scheduledAt: scheduledAt, imageUrls: imageUrls, videoUrls: videoUrls,
            pushedMessageId: pushedMessageId, mastodonProviderIds: mastodonProviderIds,
            crossPostToBluesky: crossPostToBluesky, crossPostToLinkedIn: crossPostToLinkedIn,
            linkedInTargets: linkedInTargets, linkedInLinkAsFirstComment: linkedInLinkAsFirstComment,
            crossPostToTwitter: crossPostToTwitter, scheduledCrossPostConfig: scheduledCrossPostConfig,
            organizationId: organizationId
        )
    }

    func test_encode_organizationId_presentWhenSet() throws {
        let body = makeBody(content: "Org post", publiclyVisible: true, organizationId: "org-42")
        let json = try encodedJSON(body)
        XCTAssertEqual(json["organizationId"] as? String, "org-42")
        XCTAssertNil(json["organization_id"])
    }

    func test_encode_organizationId_absentWhenNil() throws {
        let body = makeBody(content: "Personal post")
        let json = try encodedJSON(body)
        XCTAssertNil(json["organizationId"])
    }

    func test_encode_organizationId_doesNotAffectOtherFields() throws {
        let body = makeBody(content: "Hello", publiclyVisible: true, tags: ["swift"], organizationId: "org-99")
        let json = try encodedJSON(body)
        XCTAssertEqual(json["content"] as? String, "Hello")
        XCTAssertEqual(json["publiclyVisible"] as? Bool, true)
        XCTAssertEqual(json["tags"] as? [String], ["swift"])
        XCTAssertEqual(json["organizationId"] as? String, "org-99")
    }
}

final class PaginationCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_allFields() throws {
        let json = #"{"total":100,"limit":50,"offset":0,"has_more":true}"#
        let p = try decoder.decode(Pagination.self, from: Data(json.utf8))
        XCTAssertEqual(p.total, 100)
        XCTAssertEqual(p.limit, 50)
        XCTAssertEqual(p.offset, 0)
        XCTAssertTrue(p.hasMore)
    }

    func test_decode_hasMore_false() throws {
        let json = #"{"total":5,"limit":20,"offset":20,"has_more":false}"#
        let p = try decoder.decode(Pagination.self, from: Data(json.utf8))
        XCTAssertEqual(p.total, 5)
        XCTAssertEqual(p.limit, 20)
        XCTAssertEqual(p.offset, 20)
        XCTAssertFalse(p.hasMore)
    }
}
