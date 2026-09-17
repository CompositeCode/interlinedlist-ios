import XCTest
@testable import InterlinedList

/// Every route that puts a user-typed term or a server-issued opaque cursor into
/// a query value, checked through the one shared `queryValue(_:)` encoder.
///
/// Two failure modes are being guarded against, and only one of them is visible
/// to `URLComponents`: a raw `&` or `=` splits the value into an extra query
/// parameter (so the round-trip and the parameter count both catch it), while a
/// raw `+` survives `URLComponents` intact and only goes wrong on the backend,
/// which reads params through `URLSearchParams` and decodes `+` as a space.
/// That is why each case also asserts the *wire* form carries no literal `+`.
final class APIClientQueryValueEncodingTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    /// Contains all four of `+`, `&`, `=` and a space.
    private let awkwardTerm = "c++ & a=b"
    /// Base64 alphabet output, containing `+`, `/` and the `=` padding.
    private let base64Cursor = "YWJjKz0vZGVm+/w=="

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func assertQueryValueSurvives(_ expected: String,
                                          named name: String,
                                          parameterCount: Int,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) throws {
        let url = try XCTUnwrap(session.lastRequest?.url, file: file, line: line)
        let rawQuery = url.query ?? ""
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.count, parameterCount,
                       "The value must not split into extra parameters: \(rawQuery)",
                       file: file, line: line)
        XCTAssertEqual(items.first(where: { $0.name == name })?.value, expected,
                       "Expected \(name) to round-trip unchanged: \(rawQuery)",
                       file: file, line: line)
        XCTAssertFalse(rawQuery.contains("+"),
                       "A literal + reaches the backend as a space: \(rawQuery)",
                       file: file, line: line)
    }

    // MARK: - Search terms

    func test_searchMessages_termWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(json: #"{"messages":[],"pagination":null}"#)
        _ = try await sut.searchMessages(q: awkwardTerm)
        try assertQueryValueSurvives(awkwardTerm, named: "q", parameterCount: 3)
    }

    func test_searchDocuments_termWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(json: #"{"documents":[],"pagination":null}"#)
        _ = try await sut.searchDocuments(q: awkwardTerm)
        try assertQueryValueSurvives(awkwardTerm, named: "q", parameterCount: 3)
    }

    func test_searchLists_termWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(json: #"{"lists":[],"pagination":null}"#)
        _ = try await sut.searchLists(q: awkwardTerm)
        try assertQueryValueSurvives(awkwardTerm, named: "q", parameterCount: 3)
    }

    func test_searchWatcherCandidates_termWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.searchWatcherCandidates(listId: "list-1", search: awkwardTerm)
        try assertQueryValueSurvives(awkwardTerm, named: "search", parameterCount: 3)
    }

    func test_searchDocumentCollaboratorCandidates_termWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.searchDocumentCollaboratorCandidates(id: "doc-1", query: awkwardTerm)
        try assertQueryValueSurvives(awkwardTerm, named: "q", parameterCount: 1)
    }

    func test_organizationUsers_termWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(json: #"{"users":[],"total":0}"#)
        _ = try await sut.organizationUsers(id: "org-1", search: awkwardTerm)
        try assertQueryValueSurvives(awkwardTerm, named: "search", parameterCount: 3)
    }

    // MARK: - Opaque cursors

    func test_dmThreadUpdates_base64CursorWithPadding_roundTripsUnchanged() async throws {
        session.stub(json: threadJSON)
        _ = try await sut.dmThreadUpdates(username: "bob", after: base64Cursor)
        try assertQueryValueSurvives(base64Cursor, named: "after", parameterCount: 1)
    }

    func test_dmConversations_base64CursorWithPadding_roundTripsUnchanged() async throws {
        session.stub(json: #"{"items":[],"nextCursor":null}"#)
        _ = try await sut.dmConversations(cursor: base64Cursor)
        try assertQueryValueSurvives(base64Cursor, named: "cursor", parameterCount: 1)
    }

    func test_unlinkIdentity_providerWithQueryDelimiters_roundTripsUnchanged() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.unlinkIdentity(provider: "mastodon:a+b&c=d")
        try assertQueryValueSurvives("mastodon:a+b&c=d", named: "provider", parameterCount: 1)
    }

    // MARK: - Path encoding is left alone

    /// `pathSegment(_:)` and `queryValue(_:)` are not interchangeable: a slash in
    /// a *path* segment still has to be escaped, and encoding the two halves of a
    /// URL with one set would break whichever half it wasn't chosen for.
    func test_dmThreadUpdates_usernameStaysPathEncoded() async throws {
        session.stub(json: threadJSON)
        _ = try await sut.dmThreadUpdates(username: "bob smith", after: "m1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/dm/thread/bob smith/updates")
    }

    private let threadJSON = #"""
    {"items":[],"olderCursor":null,"isMutual":true,"isBlocked":false,
     "otherUser":{"id":"r1","username":"bob","displayName":"Bob","avatar":null}}
    """#
}
