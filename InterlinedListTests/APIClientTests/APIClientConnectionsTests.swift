import XCTest
@testable import InterlinedList

final class APIClientConnectionsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("test-token")
    }

    func test_listConnections_sendsGetToCorrectPath() async throws {
        let json = #"""
        {"connections":[{"id":"c1","sourceListId":"s1","targetListId":"t1","createdAt":"2024-01-01T00:00:00Z"}]}
        """#
        session.stub(json: json)
        let result = try await sut.listConnections()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/connections")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "c1")
    }

    func test_createListConnection_sendsPostWithSourceAndTarget() async throws {
        let json = #"""
        {"connection":{"id":"c2","sourceListId":"src","targetListId":"tgt","createdAt":null}}
        """#
        session.stub(json: json)
        let conn = try await sut.createListConnection(sourceListId: "src", targetListId: "tgt")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/connections")
        let bodyData = try XCTUnwrap(session.lastRequest?.httpBody)
        let bodyJSON = try JSONSerialization.jsonObject(with: bodyData) as? [String: String]
        XCTAssertEqual(bodyJSON?["sourceListId"], "src")
        XCTAssertEqual(bodyJSON?["targetListId"], "tgt")
        XCTAssertEqual(conn.id, "c2")
    }

    func test_deleteListConnection_sendsDeleteToCorrectPath() async throws {
        session.stub(json: "{}", statusCode: 200)
        try await sut.deleteListConnection(id: "conn-99")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/connections/conn-99")
    }

    func test_listConnections_401_throwsStatusError() async throws {
        session.stub(json: #"{"error":"unauthorized"}"#, statusCode: 401)
        do {
            _ = try await sut.listConnections()
            XCTFail("Expected APIError.status(401)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
