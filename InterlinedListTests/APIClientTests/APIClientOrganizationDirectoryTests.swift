import XCTest
@testable import InterlinedList

/// Request/response shapes for the three organization routes wired up by the
/// add-member and discover flows: the owner-gated candidate search, the
/// add-member write, and the public directory + join.
final class APIClientOrganizationDirectoryTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func queryItems() throws -> [String: String] {
        let url = try XCTUnwrap(session.lastRequest?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func bodyObject() throws -> [String: Any] {
        let data = try XCTUnwrap(session.lastRequest?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - organizationUsers (candidate search)

    func test_organizationUsers_sendsOwnerGatedPath() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/organizations/org-1/users")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_organizationUsers_sendsPagingDefaults() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1")
        let items = try queryItems()
        XCTAssertEqual(items["limit"], "20")
        XCTAssertEqual(items["offset"], "0")
        XCTAssertNil(items["search"])
        XCTAssertNil(items["excludeMembers"])
    }

    /// `.urlQueryAllowed` permits `&`, so encoding with it would let a typed `&`
    /// split the query and truncate the term to "ada l".
    func test_organizationUsers_percentEncodesAmpersandInSearch() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", search: "ada l&ve")
        XCTAssertEqual(try queryItems()["search"], "ada l&ve")
        XCTAssertEqual(try queryItems().count, 3, "The search term must not add a query parameter")
        let raw = try XCTUnwrap(session.lastRequest?.url?.absoluteString)
        XCTAssertTrue(raw.contains("search=ada%20l%26ve"), raw)
    }

    /// The backend reads params via `URLSearchParams`, which decodes a literal
    /// `+` as a space, so `+` has to go over the wire encoded.
    func test_organizationUsers_percentEncodesPlusInSearch() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", search: "c++")
        let raw = try XCTUnwrap(session.lastRequest?.url?.absoluteString)
        XCTAssertTrue(raw.contains("search=c%2B%2B"), raw)
    }

    func test_organizationUsers_keepsExcludeMembersCommasUnencoded() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", excludeMembers: ["u1", "u2"])
        let raw = try XCTUnwrap(session.lastRequest?.url?.absoluteString)
        XCTAssertTrue(raw.contains("excludeMembers=u1,u2"), "The backend splits this list on a literal comma: \(raw)")
    }

    func test_organizationUsers_emptySearchIsOmitted() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", search: "")
        XCTAssertNil(try queryItems()["search"])
    }

    func test_organizationUsers_joinsExcludeMembersWithCommas() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", excludeMembers: ["u1", "u2", "u3"])
        XCTAssertEqual(try queryItems()["excludeMembers"], "u1,u2,u3")
    }

    func test_organizationUsers_emptyExcludeMembersIsOmitted() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", excludeMembers: [])
        XCTAssertNil(try queryItems()["excludeMembers"])
    }

    func test_organizationUsers_percentEncodesOrgIdInPath() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org 1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/organizations/org 1/users")
    }

    /// The route answers `{ users, total, pagination: { limit, offset, hasMore } }`.
    /// That `pagination` block has no `total`, so decoding it into the shared
    /// `Pagination` type would throw — the response model must ignore it.
    func test_organizationUsers_decodesUsersDespitePaginationWithoutTotal() async throws {
        let json = """
        {"users":[
          {"id":"u1","username":"ada","displayName":"Ada Lovelace","email":"ada@example.com","avatar":"https://x/a.png","createdAt":"2026-01-01T00:00:00.000Z"},
          {"id":"u2","username":"bob","displayName":null,"email":null,"avatar":null,"createdAt":"2026-01-02T00:00:00.000Z"}
        ],"total":2,"pagination":{"limit":20,"offset":0,"hasMore":false}}
        """
        session.stub(json: json)
        let users = try await sut.organizationUsers(id: "org-1")
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users[0].id, "u1")
        XCTAssertEqual(users[0].displayNameOrUsername, "Ada Lovelace")
        XCTAssertEqual(users[0].email, "ada@example.com")
        XCTAssertNil(users[1].displayName)
        XCTAssertNil(users[1].email)
        XCTAssertEqual(users[1].displayNameOrUsername, "bob")
    }

    /// Non-owners get a 403 *with* an `error` body, which the transport maps to
    /// `.forbidden` — not `.status(403)`. The add-member affordance keys off this.
    func test_organizationUsers_nonOwner403_throwsForbiddenNotStatus() async throws {
        session.stub(
            json: #"{"error":"Only organization owners can search for users to add","code":"forbidden"}"#,
            statusCode: 403
        )
        do {
            _ = try await sut.organizationUsers(id: "org-1")
            XCTFail("Expected throw")
        } catch APIError.forbidden(let message) {
            XCTAssertEqual(message, "Only organization owners can search for users to add")
        }
    }

    func test_organizationUsers_401_throwsStatus401() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.organizationUsers(id: "org-1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: - addOrganizationMember

    func test_addOrganizationMember_sendsCamelCaseBodyToMembersPath() async throws {
        session.stub(json: #"{"message":"User added to organization successfully","membership":{"id":"m1"}}"#, statusCode: 201)
        try await sut.addOrganizationMember(id: "org-1", userId: "u1", role: .admin)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/organizations/org-1/members")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        let body = try bodyObject()
        XCTAssertEqual(body["userId"] as? String, "u1")
        XCTAssertEqual(body["role"] as? String, "admin")
        XCTAssertNil(body["user_id"], "Body must be camelCase — this route rejects snake_case keys")
    }

    func test_addOrganizationMember_sendsMemberRoleRawValue() async throws {
        session.stub(json: #"{"message":"ok"}"#, statusCode: 201)
        try await sut.addOrganizationMember(id: "org-1", userId: "u1", role: .member)
        XCTAssertEqual(try bodyObject()["role"] as? String, "member")
    }

    func test_addOrganizationMember_201WithMembershipBodyDoesNotThrow() async throws {
        session.stub(json: #"{"message":"User added to organization successfully","membership":{"id":"m1","role":"member"}}"#, statusCode: 201)
        try await sut.addOrganizationMember(id: "org-1", userId: "u1", role: .member)
        XCTAssertEqual(session.requestHistory.count, 1)
    }

    func test_addOrganizationMember_alreadyMember409_throwsConflict() async throws {
        session.stub(json: #"{"error":"User is already a member","code":"conflict"}"#, statusCode: 409)
        do {
            try await sut.addOrganizationMember(id: "org-1", userId: "u1", role: .member)
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "User is already a member")
        }
    }

    // MARK: - joinOrganization

    func test_joinOrganization_sendsCamelCaseOrganizationId() async throws {
        session.stub(json: #"{"message":"Joined organization successfully","membership":{"id":"m1"}}"#, statusCode: 201)
        try await sut.joinOrganization(organizationId: "org-9")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/organizations")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        let body = try bodyObject()
        XCTAssertEqual(body["organizationId"] as? String, "org-9")
        XCTAssertNil(body["organization_id"], "Body must be camelCase — this route reads organizationId")
    }

    func test_joinOrganization_privateOrg403_throwsForbidden() async throws {
        session.stub(
            json: #"{"error":"Cannot join private organization. An invitation is required.","code":"forbidden"}"#,
            statusCode: 403
        )
        do {
            try await sut.joinOrganization(organizationId: "org-9")
            XCTFail("Expected throw")
        } catch APIError.forbidden(let message) {
            XCTAssertEqual(message, "Cannot join private organization. An invitation is required.")
        }
    }

    // MARK: - publicOrganizations (directory)

    func test_publicOrganizations_sendsPublicTrueAndPaging() async throws {
        session.stub(json: #"{"organizations":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#)
        _ = try await sut.publicOrganizations(limit: 20, offset: 40)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/organizations")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        let items = try queryItems()
        XCTAssertEqual(items["public"], "true")
        XCTAssertEqual(items["limit"], "20")
        XCTAssertEqual(items["offset"], "40")
    }

    func test_publicOrganizations_decodesOrgsAndPagination() async throws {
        let json = """
        {"organizations":[
          {"id":"o1","name":"Acme","description":"Widgets","isPublic":true,"memberCount":12,"userRole":null},
          {"id":"o2","name":"Beta","description":null,"isPublic":true,"memberCount":3,"userRole":"member"}
        ],"pagination":{"total":42,"limit":2,"offset":0,"hasMore":true}}
        """
        session.stub(json: json)
        let result = try await sut.publicOrganizations(limit: 2, offset: 0)
        XCTAssertEqual(result.orgs.count, 2)
        XCTAssertEqual(result.orgs[0].memberCount, 12)
        XCTAssertNil(result.orgs[0].role, "No membership means the row offers Join")
        XCTAssertEqual(result.orgs[1].role, .member, "An existing membership must render as a role, not a Join")
        XCTAssertEqual(result.pagination?.total, 42)
        XCTAssertEqual(result.pagination?.hasMore, true)
    }

    func test_publicOrganizations_missingPaginationDecodesAsNil() async throws {
        session.stub(json: #"{"organizations":[{"id":"o1","name":"Acme"}]}"#)
        let result = try await sut.publicOrganizations()
        XCTAssertEqual(result.orgs.count, 1)
        XCTAssertNil(result.pagination)
    }

    func test_publicOrganizations_401_throwsStatus401() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.publicOrganizations()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }
}
