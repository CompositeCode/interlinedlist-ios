import XCTest
@testable import InterlinedList

final class APIClientDocumentPresenceTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func bodyJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(session.lastRequest?.httpBody)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: documentPresence()

    func test_presence_postsToThePresencePath() async throws {
        session.stub(json: #"{"users":[],"version":3}"#)
        _ = try await sut.documentPresence(id: "d1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/presence")
    }

    func test_presence_sendsCamelCaseCaretOffsets() async throws {
        session.stub(json: #"{"users":[],"version":null}"#)
        _ = try await sut.documentPresence(id: "d1", anchor: 12, head: 20)
        let json = try bodyJSON()
        XCTAssertEqual(json["anchor"] as? Int, 12)
        XCTAssertEqual(json["head"] as? Int, 20)
    }

    func test_presence_omitsOffsetsWhenNotReportingACaret() async throws {
        session.stub(json: #"{"users":[],"version":null}"#)
        _ = try await sut.documentPresence(id: "d1")
        let json = try bodyJSON()
        XCTAssertNil(json["anchor"], "The route treats an absent caret as present-with-no-caret")
        XCTAssertNil(json["head"])
    }

    func test_presence_decodesOtherEditorsAndVersion() async throws {
        session.stub(json: #"""
        {"users":[
          {"userId":"u2","name":"Bob","color":"#ff0000","anchor":4,"head":9},
          {"userId":"u3","name":"Cara","color":null,"anchor":null,"head":null}
        ],"version":7}
        """#)
        let response = try await sut.documentPresence(id: "d1")
        XCTAssertEqual(response.version, 7)
        XCTAssertEqual(response.users.map(\.name), ["Bob", "Cara"])
        XCTAssertEqual(response.users.first?.id, "u2")
        XCTAssertEqual(response.users.first?.anchor, 4)
        XCTAssertNil(response.users.last?.color)
    }

    func test_presence_percentEncodesTheDocumentId() async throws {
        session.stub(json: #"{"users":[],"version":null}"#)
        _ = try await sut.documentPresence(id: "a b")
        let url = try XCTUnwrap(session.lastRequest?.url?.absoluteString)
        XCTAssertFalse(url.contains("a b"), "Document id must be percent-encoded: \(url)")
        XCTAssertTrue(url.hasSuffix("/presence"))
    }

    func test_presence_404_forADocumentWithoutAccess() async throws {
        session.stub(json: #"{"error":"Document not found"}"#, statusCode: 404)
        do {
            _ = try await sut.documentPresence(id: "d1")
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "Document not found")
        }
    }

    // MARK: leaveDocumentPresence()

    func test_leave_sendsDeleteToThePresencePath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.leaveDocumentPresence(id: "d1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/presence")
    }
}
