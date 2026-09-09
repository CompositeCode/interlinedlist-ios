import XCTest
@testable import InterlinedList

/// W6 (#58). `GET /api/lists/{id}/contributors` returns the full ranked
/// contributor set with no server paging. These tests pin the route, the decode
/// of the aggregation counts the header stack renders, and the two shapes that
/// must degrade quietly: the empty set GitHub-backed lists get by design, and a
/// 403 on a list the viewer can read but not aggregate.
final class APIClientListContributorsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    /// Live shape: camelCase keys straight off `serialize()`, ranked by score
    /// descending, with `totalContributors` alongside.
    private var contributorsJSON: String {
        #"""
        {"contributors":[
          {"id":"u1","username":"adron","displayName":"Adron Hall",
           "avatar":"https://example.com/a.png","addedCount":12,"editedCount":4,"score":16},
          {"id":"u2","username":"rhea","displayName":"Rhea Kim",
           "avatar":null,"addedCount":7,"editedCount":1,"score":8},
          {"id":"u3","username":"sam","displayName":null,
           "avatar":null,"addedCount":2,"editedCount":3,"score":5}
         ],
         "totalContributors":3}
        """#
    }

    func test_listContributors_sendsGetToContributorsPath() async throws {
        session.stub(json: contributorsJSON)
        _ = try await sut.listContributors(listId: "list-1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/list-1/contributors")
    }

    func test_listContributors_percentEncodesListId() async throws {
        session.stub(json: contributorsJSON)
        _ = try await sut.listContributors(listId: "list one")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/list one/contributors")
        XCTAssertTrue(
            session.lastRequest?.url?.absoluteString.contains("list%20one") == true,
            session.lastRequest?.url?.absoluteString ?? "nil"
        )
    }

    func test_listContributors_decodesFullSetAndTotal() async throws {
        session.stub(json: contributorsJSON)
        let result = try await sut.listContributors(listId: "list-1")
        XCTAssertEqual(result.totalContributors, 3)
        XCTAssertEqual(result.contributors.count, 3)
    }

    func test_listContributors_decodesAggregationCounts() async throws {
        session.stub(json: contributorsJSON)
        let result = try await sut.listContributors(listId: "list-1")
        let top = try XCTUnwrap(result.contributors.first)
        XCTAssertEqual(top.id, "u1")
        XCTAssertEqual(top.username, "adron")
        XCTAssertEqual(top.displayName, "Adron Hall")
        XCTAssertEqual(top.avatar, "https://example.com/a.png")
        XCTAssertEqual(top.addedCount, 12)
        XCTAssertEqual(top.editedCount, 4)
        XCTAssertEqual(top.score, 16)
    }

    /// The server ranks; the client must not re-sort or the stack would disagree
    /// with the web's order.
    func test_listContributors_preservesServerRanking() async throws {
        session.stub(json: contributorsJSON)
        let result = try await sut.listContributors(listId: "list-1")
        XCTAssertEqual(result.contributors.map(\.id), ["u1", "u2", "u3"])
        XCTAssertEqual(result.contributors.map(\.score), [16, 8, 5])
    }

    /// `displayName` is nullable; the row headline falls back to the username.
    func test_contributor_nullDisplayNameFallsBackToUsername() async throws {
        session.stub(json: contributorsJSON)
        let result = try await sut.listContributors(listId: "list-1")
        let sam = try XCTUnwrap(result.contributors.last)
        XCTAssertNil(sam.displayName)
        XCTAssertEqual(sam.displayNameOrUsername, "sam")
        XCTAssertEqual(result.contributors[0].displayNameOrUsername, "Adron Hall")
    }

    /// An empty displayName is as good as absent — same fallback.
    func test_contributor_emptyDisplayNameFallsBackToUsername() throws {
        let json = #"{"id":"u9","username":"kit","displayName":"","avatar":null,"addedCount":1,"editedCount":0,"score":1}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let contributor = try decoder.decode(ListContributor.self, from: Data(json.utf8))
        XCTAssertEqual(contributor.displayNameOrUsername, "kit")
    }

    /// Matches the web's contributor subtitle exactly.
    func test_contributor_contributionSummaryMatchesWebCopy() async throws {
        session.stub(json: contributorsJSON)
        let result = try await sut.listContributors(listId: "list-1")
        XCTAssertEqual(result.contributors[0].contributionSummary, "added 12 · edited 4")
        XCTAssertEqual(result.contributors[1].contributionSummary, "added 7 · edited 1")
    }

    /// What a GitHub-backed list returns by design. It must decode cleanly, not throw.
    func test_listContributors_emptySetDecodes() async throws {
        session.stub(json: #"{"contributors":[],"totalContributors":0}"#)
        let result = try await sut.listContributors(listId: "gh-list")
        XCTAssertTrue(result.contributors.isEmpty)
        XCTAssertEqual(result.totalContributors, 0)
    }

    func test_listContributors_403_throws() async {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.listContributors(listId: "list-1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_listContributors_401_throws() async {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.listContributors(listId: "list-1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// The stack's accessibility label singularizes at one.
    func test_avatarStackLabel_pluralization() {
        XCTAssertEqual(ContributorAvatarStack.label(for: 1), "1 contributor")
        XCTAssertEqual(ContributorAvatarStack.label(for: 3), "3 contributors")
        XCTAssertEqual(ContributorAvatarStack.label(for: 0), "0 contributors")
    }
}
