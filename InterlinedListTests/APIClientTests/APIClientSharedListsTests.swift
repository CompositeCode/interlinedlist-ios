import XCTest
@testable import InterlinedList

/// G17. `GET /api/lists` is owner-scoped on the backend, so lists shared *to* the
/// user only ever arrive through `GET /api/lists/watching`. These tests pin the
/// route and the two fields the Lists tab depends on: the owner id (which drives
/// `isOwned(by:)`, and therefore whether owner-only UI shows) and the viewer's
/// own role.
final class APIClientSharedListsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    /// Shape of the live route: raw list rows plus the viewer's `role`, wrapped
    /// alongside a pagination block the client ignores.
    private var watchingJSON: String {
        #"""
        {"lists":[
          {"id":"l1","title":"Team Roadmap","description":"Q4","userId":"owner-1",
           "parentId":null,"isPublic":false,"createdAt":"2026-09-01T00:00:00.000Z",
           "updatedAt":"2026-09-02T00:00:00.000Z","source":"local","role":"collaborator"},
          {"id":"l2","title":"Conference Talks","description":null,"userId":"owner-2",
           "parentId":null,"isPublic":true,"createdAt":"2026-08-01T00:00:00.000Z",
           "updatedAt":null,"source":"local","role":"watcher"}
         ],
         "pagination":{"total":2,"limit":50,"offset":0,"hasMore":false}}
        """#
    }

    func test_listsWatching_sendsGetToWatchingPath() async throws {
        session.stub(json: watchingJSON)
        _ = try await sut.listsWatching()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/watching")
    }

    func test_listsWatching_sendsPagination() async throws {
        session.stub(json: watchingJSON)
        _ = try await sut.listsWatching(limit: 10, offset: 20)
        let query = session.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("limit=10"), query)
        XCTAssertTrue(query.contains("offset=20"), query)
    }

    func test_listsWatching_decodesListsWithTitleMappedToName() async throws {
        session.stub(json: watchingJSON)
        let lists = try await sut.listsWatching()
        XCTAssertEqual(lists.count, 2)
        XCTAssertEqual(lists.first?.name, "Team Roadmap")
        XCTAssertEqual(lists.first?.description, "Q4")
    }

    /// The point of the whole feature: these lists belong to somebody else, so
    /// every owner-only affordance must gate off.
    func test_listsWatching_listsAreNotOwnedByViewer() async throws {
        session.stub(json: watchingJSON)
        let lists = try await sut.listsWatching()
        XCTAssertEqual(lists.first?.ownerId, "owner-1")
        XCTAssertFalse(lists[0].isOwned(by: "me"))
        XCTAssertFalse(lists[1].isOwned(by: "me"))
    }

    func test_listsWatching_decodesViewerRole() async throws {
        session.stub(json: watchingJSON)
        let lists = try await sut.listsWatching()
        XCTAssertEqual(lists[0].watcherRole, .collaborator)
        XCTAssertEqual(lists[1].watcherRole, .watcher)
        XCTAssertTrue(lists[0].watcherRole?.canEditRows == true)
        XCTAssertFalse(lists[1].watcherRole?.canEditRows == true)
    }

    func test_listsWatching_emptyResponseDecodesToEmptyArray() async throws {
        session.stub(json: #"{"lists":[],"pagination":{"total":0,"limit":50,"offset":0,"hasMore":false}}"#)
        let lists = try await sut.listsWatching()
        XCTAssertTrue(lists.isEmpty)
    }

    /// An owned list carries no `role`, and `isOwned(by:)` still answers true.
    func test_ownedList_hasNilRole() throws {
        let json = #"{"id":"l9","title":"Mine","userId":"me","isPublic":false,"createdAt":"2026-09-01T00:00:00.000Z"}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertNil(list.role)
        XCTAssertNil(list.watcherRole)
        XCTAssertTrue(list.isOwned(by: "me"))
    }

    /// An unrecognized wire role must not crash the row — it degrades to nil and
    /// the label is simply omitted.
    func test_unknownRole_decodesToNilWatcherRole() throws {
        let json = #"{"id":"l9","title":"Mine","userId":"other","isPublic":false,"createdAt":"2026-09-01T00:00:00.000Z","role":"archivist"}"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.role, "archivist")
        XCTAssertNil(list.watcherRole)
    }

    func test_listsWatching_401_throws() async {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.listsWatching()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
