import XCTest
@testable import InterlinedList

final class APIClientDeleteAccountTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_deleteAccount_sendsCorrectPath() async throws {
        session.stub(json: #"{"message":"deleted"}"#)
        try await sut.deleteAccount()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/delete")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_deleteAccount_sendsBearerToken() async throws {
        session.stub(json: #"{"message":"deleted"}"#)
        try await sut.deleteAccount()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_deleteAccount_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.deleteAccount()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_deleteAccount_500_throws() async throws {
        session.stub(data: Data(), statusCode: 500)
        do {
            try await sut.deleteAccount()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 500)
        }
    }
}
