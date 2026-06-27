import XCTest
@testable import InterlinedList

final class APIClientOrganizationsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_userOrganizations_sendsCorrectPath() async throws {
        session.stub(json: #"{"organizations":[]}"#)
        _ = try await sut.userOrganizations()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/organizations")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
    }

    func test_userOrganizations_decodesArray() async throws {
        let json = """
        {"organizations":[
          {"id":"o1","name":"Acme","description":"Co","isPublic":true},
          {"id":"o2","name":"Beta","description":null,"isPublic":false}
        ]}
        """
        session.stub(json: json)
        let orgs = try await sut.userOrganizations()
        XCTAssertEqual(orgs.count, 2)
        XCTAssertEqual(orgs[0].name, "Acme")
        XCTAssertEqual(orgs[0].isPublic, true)
        XCTAssertNil(orgs[1].description)
    }

    func test_userOrganizations_sendsBearerToken() async throws {
        session.stub(json: #"{"organizations":[]}"#)
        _ = try await sut.userOrganizations()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_userOrganizations_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.userOrganizations()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_userOrganizations_emptyResponse_returnsEmptyArray() async throws {
        session.stub(json: #"{}"#)
        let orgs = try await sut.userOrganizations()
        XCTAssertTrue(orgs.isEmpty)
    }
}
