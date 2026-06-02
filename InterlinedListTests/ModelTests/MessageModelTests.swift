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
}
