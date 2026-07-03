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
