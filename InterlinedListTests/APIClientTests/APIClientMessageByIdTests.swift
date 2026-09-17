import XCTest
@testable import InterlinedList

final class APIClientMessageByIdTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let bareMessageJSON = #"{"id":"m1","content":"Hello","user_id":"u1","created_at":"2024-01-01T00:00:00Z"}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_message_sendsGetToCorrectPath() async throws {
        session.stub(json: bareMessageJSON)
        _ = try await sut.message(id: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1")
    }

    func test_message_sendsBearerToken() async throws {
        session.stub(json: bareMessageJSON)
        _ = try await sut.message(id: "m1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_message_percentEncodesId() async throws {
        session.stub(json: bareMessageJSON)
        _ = try await sut.message(id: "a b")
        let urlString = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertFalse(urlString.contains("a b"))
        XCTAssertTrue(urlString.contains("a%20b"))
    }

    func test_message_decodesBareObject() async throws {
        session.stub(json: bareMessageJSON)
        let message = try await sut.message(id: "m1")
        XCTAssertEqual(message.id, "m1")
        XCTAssertEqual(message.content, "Hello")
        XCTAssertEqual(message.userId, "u1")
    }

    func test_message_decodesMessageWrapper() async throws {
        session.stub(json: #"{"message":\#(bareMessageJSON)}"#)
        let message = try await sut.message(id: "m1")
        XCTAssertEqual(message.id, "m1")
    }

    func test_message_decodesDataWrapper() async throws {
        session.stub(json: #"{"data":\#(bareMessageJSON)}"#)
        let message = try await sut.message(id: "m1")
        XCTAssertEqual(message.id, "m1")
    }

    func test_message_404_throwsAPIError() async throws {
        session.stub(json: #"{"error":"Message not found"}"#, statusCode: 404)
        do {
            _ = try await sut.message(id: "missing")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "Message not found")
        }
    }

    func test_message_404_withoutErrorBody_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 404)
        do {
            _ = try await sut.message(id: "missing")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 404)
        }
    }

    func test_message_401_throwsStatus401() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.message(id: "m1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: crossPostReplyCounts() — #62

    func test_crossPostReplyCounts_postsToTheReplyCountsPath() async throws {
        session.stub(json: #"{"replyCounts":[],"repliesCheckedAt":"2026-09-15T00:00:00.000Z"}"#)
        _ = try await sut.crossPostReplyCounts(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages/m1/reply-counts")
    }

    func test_crossPostReplyCounts_decodesEntries() async throws {
        session.stub(json: #"""
        {"replyCounts":[
          {"platform":"bluesky","count":12,"status":"success","checkedAt":"2026-09-15T00:00:00.000Z"},
          {"platform":"mastodon","count":4,"status":"success","checkedAt":"2026-09-15T00:00:00.000Z"},
          {"platform":"linkedin","status":"unsupported","checkedAt":"2026-09-15T00:00:00.000Z"},
          {"platform":"twitter","status":"error","checkedAt":"2026-09-15T00:00:00.000Z"}
        ],"repliesCheckedAt":"2026-09-15T00:00:00.000Z"}
        """#)
        let response = try await sut.crossPostReplyCounts(messageId: "m1")
        XCTAssertEqual(response.replyCounts.count, 4)
        XCTAssertEqual(response.repliesCheckedAt, "2026-09-15T00:00:00.000Z")

        // Only `success` entries with a count are worth drawing.
        let displayable = response.replyCounts.filter(\.isDisplayable)
        XCTAssertEqual(displayable.map(\.platform), ["bluesky", "mastodon"])
        XCTAssertEqual(displayable.first?.count, 12)

        let unsupported = try XCTUnwrap(response.replyCounts.first { $0.platform == "linkedin" })
        XCTAssertFalse(unsupported.isDisplayable)
        XCTAssertNil(unsupported.count)
        let errored = try XCTUnwrap(response.replyCounts.first { $0.platform == "twitter" })
        XCTAssertFalse(errored.isDisplayable)
    }

    func test_crossPostReplyCounts_percentEncodesTheMessageId() async throws {
        session.stub(json: #"{"replyCounts":[],"repliesCheckedAt":null}"#)
        _ = try await sut.crossPostReplyCounts(messageId: "a b/c")
        let url = try XCTUnwrap(session.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.hasSuffix("/reply-counts"), "URL was \(url)")
        XCTAssertFalse(url.contains("a b"), "Message id must be percent-encoded: \(url)")
    }

    func test_crossPostReplyCounts_429_throwsSoTheCallerCanSwallowIt() async throws {
        session.stub(json: #"{"error":"Too many requests. Please try again later."}"#, statusCode: 429)
        do {
            _ = try await sut.crossPostReplyCounts(messageId: "m1")
            XCTFail("Expected a throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "Too many requests. Please try again later.")
        }
    }
}
