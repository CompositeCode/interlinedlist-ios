import XCTest
@testable import InterlinedList

final class APIClientPushTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: registerPushDevice()

    func test_registerPushDevice_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"registered":true}"#)
        try await sut.registerPushDevice(token: "abc")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/push/register")
    }

    func test_registerPushDevice_sendsBearerToken() async throws {
        session.stub(json: #"{"registered":true}"#)
        try await sut.registerPushDevice(token: "abc")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_registerPushDevice_bodyContainsTokenAndPlatform() async throws {
        session.stub(json: #"{"registered":true}"#)
        try await sut.registerPushDevice(token: "abc")
        let bodyData = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["token"] as? String, "abc")
        XCTAssertEqual(json?["platform"] as? String, "ios")
    }

    func test_registerPushDevice_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.registerPushDevice(token: "abc")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: unregisterPushDevice()

    func test_unregisterPushDevice_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.unregisterPushDevice(token: "abc")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/push/unregister")
    }

    func test_unregisterPushDevice_bodyContainsToken() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.unregisterPushDevice(token: "abc")
        let bodyData = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        XCTAssertEqual(json?["token"] as? String, "abc")
    }
}
