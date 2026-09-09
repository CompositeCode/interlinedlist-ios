import XCTest
@testable import InterlinedList

/// W7. `GET /api/lists/:id` is what makes a bare `/lists/<id>` permalink openable:
/// it is Bearer-ready and authorizes by role, so the URL needs no owner username.
/// These pin the route, the `{ data: … }` envelope, and — the part a permalink
/// depends on — that a 403/404 surfaces as "no access" rather than a generic
/// server error the opener cannot tell apart from a real failure.
final class APIClientSingleListTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    /// Shape of the live route: the whole list row under `data`.
    private var listJSON: String {
        #"""
        {"data":{"id":"l1","title":"Team Roadmap","description":"Q4","userId":"owner-1",
         "parentId":null,"isPublic":false,"createdAt":"2026-09-01T00:00:00.000Z",
         "updatedAt":"2026-09-02T00:00:00.000Z","source":"local"}}
        """#
    }

    func test_list_sendsGetToListPath() async throws {
        session.stub(json: listJSON)
        _ = try await sut.list(id: "l1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1")
    }

    func test_list_sendsBearerToken() async throws {
        session.stub(json: listJSON)
        _ = try await sut.list(id: "l1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_list_percentEncodesId() async throws {
        session.stub(json: listJSON)
        _ = try await sut.list(id: "a b")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString.hasSuffix("/api/lists/a%20b"), true)
    }

    func test_list_decodesTitleAsNameAndOwner() async throws {
        session.stub(json: listJSON)
        let list = try await sut.list(id: "l1")
        XCTAssertEqual(list.id, "l1")
        XCTAssertEqual(list.name, "Team Roadmap")
        XCTAssertEqual(list.ownerId, "owner-1")
        XCTAssertFalse(list.isOwned(by: "someone-else"))
    }

    /// The backend answers a forbidden list with a body, which the generic mapping
    /// would turn into `.forbidden` — the endpoint must normalise it instead.
    func test_list_forbiddenWithBody_throwsNoAccess() async {
        session.stub(json: #"{"error":"Forbidden","code":"forbidden"}"#, statusCode: 403)
        await assertNoAccess()
    }

    /// A list the viewer has no access record for comes back 404 with a body,
    /// which would otherwise flatten into `.server("List not found")`.
    func test_list_notFoundWithBody_throwsNoAccess() async {
        session.stub(json: #"{"error":"List not found","code":"not_found"}"#, statusCode: 404)
        await assertNoAccess()
    }

    func test_list_bodylessForbidden_throwsNoAccess() async {
        session.stub(json: "", statusCode: 403)
        await assertNoAccess()
    }

    /// 401 still means "re-check the session", never "no access" — the view routes
    /// it to `handleUnauthorized()` instead of the no-access state.
    func test_list_unauthorized_throwsStatus401() async {
        session.stub(json: #"{"error":"Unauthorized"}"#, statusCode: 401)
        do {
            _ = try await sut.list(id: "l1")
            XCTFail("expected 401")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_list_serverError_isNotReportedAsNoAccess() async {
        session.stub(json: #"{"error":"Something went wrong"}"#, statusCode: 500)
        do {
            _ = try await sut.list(id: "l1")
            XCTFail("expected failure")
        } catch is ListAccessError {
            XCTFail("a 500 must not read as no access")
        } catch {
            // Any other mapping is fine; the point is it isn't `noAccess`.
        }
    }

    private func assertNoAccess(file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await sut.list(id: "l1")
            XCTFail("expected noAccess", file: file, line: line)
        } catch ListAccessError.noAccess {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
}
