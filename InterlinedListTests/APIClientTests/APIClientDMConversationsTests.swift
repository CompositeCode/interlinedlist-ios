import XCTest
@testable import InterlinedList

final class APIClientDMConversationsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private let pageOne = #"""
    {"items":[
      {"pairKey":"a|b","otherUser":{"id":"u2","username":"bob","displayName":"Bob","avatar":null},
       "lastMessageId":"m9","lastBody":"see you then","preview":"see you then",
       "lastImageUrls":[],"lastCreatedAt":"2026-09-15T10:00:00.000Z","isMine":false,"unreadCount":3},
      {"pairKey":"a|c","otherUser":{"id":"u3","username":"cara","displayName":null,"avatar":null},
       "lastMessageId":"m8","lastBody":"","preview":"[image]",
       "lastImageUrls":["https://x/1.png"],"lastCreatedAt":"2026-09-15T09:00:00.000Z","isMine":true,"unreadCount":0}
    ],"nextCursor":"Y3Vyc29yKzEvMj0="}
    """#

    // MARK: Request shape

    func test_dmConversations_getsTheConversationsPath() async throws {
        session.stub(json: pageOne)
        _ = try await sut.dmConversations()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/conversations")
        XCTAssertNil(session.lastRequest?.url?.query, "No cursor means no query string")
    }

    func test_dmConversations_sendsBearerToken() async throws {
        session.stub(json: pageOne)
        _ = try await sut.dmConversations()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_dmConversations_percentEncodesTheBase64Cursor() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        // A real keyset cursor is base64 and can carry +, / and =. Left raw, `+`
        // decodes to a space server-side and the cursor stops matching.
        // Real base64 output containing the three characters `.urlQueryAllowed` lets through.
        let cursor = "MjAyNi0wOS0xNVQxMDowMDowMC4wMDBafG05fn77/w+="
        _ = try await sut.dmConversations(cursor: cursor)
        let query = try XCTUnwrap(session.lastRequest?.url?.query)
        XCTAssertFalse(query.contains("+"), "A raw + would decode as a space: \(query)")
        XCTAssertTrue(query.contains("%2B"), "Expected + to be escaped: \(query)")
        XCTAssertTrue(query.contains("%2F"), "Expected / to be escaped: \(query)")
        XCTAssertTrue(query.contains("%3D"), "Expected = to be escaped: \(query)")

        // And it must survive the round trip unchanged.
        let decoded = try XCTUnwrap(
            URLComponents(url: XCTUnwrap(session.lastRequest?.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cursor" })?.value
        )
        XCTAssertEqual(decoded, cursor)
    }

    func test_dmConversations_sendsTakeWhenGiven() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        _ = try await sut.dmConversations(take: 25)
        XCTAssertEqual(session.lastRequest?.url?.query, "take=25")
    }

    // MARK: Decode

    func test_dmConversations_decodesItemsAndCursor() async throws {
        session.stub(json: pageOne)
        let page = try await sut.dmConversations()
        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.nextCursor, "Y3Vyc29yKzEvMj0=")

        let first = page.items[0]
        XCTAssertEqual(first.id, "a|b", "A conversation is identified by pairKey")
        XCTAssertEqual(first.otherUser.username, "bob")
        XCTAssertEqual(first.unreadCount, 3)
        XCTAssertEqual(first.unreadBadge, "3")
        XCTAssertFalse(first.isMine)
        XCTAssertEqual(first.previewText, "see you then")
    }

    func test_imageOnlyConversationUsesTheServerPreview() async throws {
        session.stub(json: pageOne)
        let page = try await sut.dmConversations()
        let cara = try XCTUnwrap(page.items.last)
        XCTAssertEqual(cara.previewText, "[image]")
        XCTAssertTrue(cara.isMine)
        XCTAssertNil(cara.unreadBadge, "A read conversation shows no pill")
    }

    func test_unreadBadge_capsAt99Plus() throws {
        let json = #"""
        {"items":[{"pairKey":"p","otherUser":{"id":"u","username":"u","displayName":null,"avatar":null},
          "lastMessageId":"m","lastBody":"hi","preview":"hi","lastImageUrls":[],
          "lastCreatedAt":"2026-09-15T10:00:00.000Z","isMine":false,"unreadCount":250}],"nextCursor":null}
        """#
        let decoder = JSONDecoder()
        let page = try decoder.decode(DMConversationPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.items.first?.unreadBadge, "99+")
    }

    func test_lastPageHasNoCursor() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        let page = try await sut.dmConversations(cursor: "abc")
        XCTAssertNil(page.nextCursor)
        XCTAssertTrue(page.items.isEmpty)
    }

    func test_dmConversations_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.dmConversations()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
