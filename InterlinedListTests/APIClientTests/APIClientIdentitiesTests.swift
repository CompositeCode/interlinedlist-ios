import XCTest
@testable import InterlinedList

final class APIClientIdentitiesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: linkedIdentities

    func test_linkedIdentities_sendsCorrectPath() async throws {
        session.stub(json: #"{"identities":[]}"#)
        _ = try await sut.linkedIdentities()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/identities")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
    }

    func test_linkedIdentities_decodesArray() async throws {
        let json = """
        {"identities":[
          {"id":"a1","provider":"github","providerUsername":"octo","createdAt":"2026-01-01T00:00:00Z"},
          {"id":"b2","provider":"mastodon","providerUsername":"@me@mas.social","createdAt":null}
        ]}
        """
        session.stub(json: json)
        let identities = try await sut.linkedIdentities()
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(identities[0].provider, "github")
        XCTAssertEqual(identities[0].providerUsername, "octo")
        XCTAssertEqual(identities[1].provider, "mastodon")
        XCTAssertNil(identities[1].createdAt)
    }

    func test_linkedIdentities_403_throws() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.linkedIdentities()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    func test_linkedIdentities_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.linkedIdentities()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_linkedIdentities_emptyResponse_returnsEmptyArray() async throws {
        session.stub(json: #"{}"#)
        let identities = try await sut.linkedIdentities()
        XCTAssertTrue(identities.isEmpty)
    }

    // MARK: unlinkIdentity

    func test_unlinkIdentity_sendsDeleteWithBody() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.unlinkIdentity(provider: "github", providerId: "abc-123")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/identities")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"provider\":\"github\""))
        XCTAssertTrue(body.contains("\"providerId\":\"abc-123\""),
                      "Body must use camelCase providerId. Got: \(body)")
    }

    func test_unlinkIdentity_sendsBearerToken() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.unlinkIdentity(provider: "github", providerId: "x")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_unlinkIdentity_403_throws() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            try await sut.unlinkIdentity(provider: "github", providerId: "x")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    // MARK: verifyIdentity

    func test_verifyIdentity_sendsCorrectPath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.verifyIdentity(provider: "bluesky", providerId: "did:plc:abc")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/identities/verify")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
    }

    func test_verifyIdentity_bodyUsesCamelCase() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.verifyIdentity(provider: "bluesky", providerId: "did:plc:abc")
        let body = String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"providerId\":\"did:plc:abc\""), "Got: \(body)")
    }
}
