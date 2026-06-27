import XCTest
@testable import InterlinedList

final class APIClientExportTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("test-token")
    }

    func test_exportCSV_messages_sendsGetToCorrectPath() async throws {
        session.stub(data: Data("id,content\n".utf8))
        let data = try await sut.exportCSV(.messages)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/exports/messages")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(String(data: data, encoding: .utf8), "id,content\n")
    }

    func test_exportCSV_lists_sendsGetToCorrectPath() async throws {
        session.stub(data: Data("id,name\n".utf8))
        let data = try await sut.exportCSV(.lists)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/exports/lists")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(String(data: data, encoding: .utf8), "id,name\n")
    }

    func test_exportCSV_follows_sendsGetToCorrectPath() async throws {
        session.stub(data: Data("follower_id,following_id\n".utf8))
        let data = try await sut.exportCSV(.follows)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/exports/follows")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(String(data: data, encoding: .utf8), "follower_id,following_id\n")
    }

    func test_exportCSV_401_throwsStatusError() async throws {
        session.stub(json: #"{"error":"unauthorized"}"#, statusCode: 401)
        do {
            _ = try await sut.exportCSV(.messages)
            XCTFail("Expected APIError.status(401)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_exportCSV_serverError_throwsServerError() async throws {
        session.stub(json: #"{"error":"export unavailable"}"#, statusCode: 500)
        do {
            _ = try await sut.exportCSV(.messages)
            XCTFail("Expected APIError.server")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "export unavailable")
        }
    }
}
