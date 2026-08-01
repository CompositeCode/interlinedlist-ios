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
}
