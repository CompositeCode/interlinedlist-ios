import XCTest
@testable import InterlinedList

final class APIClientSharingTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let linkJSON = #"{"token":"tok123","url":"https://interlinedlist.com/s/tok123","role":"collaborator","expiresAt":"2026-08-10T00:00:00Z"}"#
    private let collaboratorJSON = #"{"userId":"u1","role":"watcher","username":"alice","displayName":"Alice","avatar":null}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func bodyString() -> String {
        guard let data = session.lastRequest?.httpBody else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - shareLinks()

    func test_shareLinks_lists_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"shareLinks":[]}"#)
        _ = try await sut.shareLinks(kind: .lists, id: "l1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/share-links")
    }

    func test_shareLinks_documents_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"shareLinks":[]}"#)
        _ = try await sut.shareLinks(kind: .documents, id: "d1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/share-links")
    }

    func test_shareLinks_decodesArray() async throws {
        session.stub(json: #"{"shareLinks":[\#(linkJSON)]}"#)
        let links = try await sut.shareLinks(kind: .lists, id: "l1")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.token, "tok123")
        XCTAssertEqual(links.first?.shareRole, .collaborator)
        XCTAssertEqual(links.first?.expiresAt, "2026-08-10T00:00:00Z")
    }

    func test_shareLinks_sendsAuthorizationHeader() async throws {
        session.stub(json: #"{"shareLinks":[]}"#)
        _ = try await sut.shareLinks(kind: .lists, id: "l1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_shareLinks_404_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 404)
        do {
            _ = try await sut.shareLinks(kind: .lists, id: "l1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 404)
        }
    }

    // MARK: - createShareLink()

    func test_createShareLink_lists_postsToCorrectPath() async throws {
        session.stub(json: linkJSON)
        _ = try await sut.createShareLink(kind: .lists, id: "l1", role: .collaborator, expiresAt: "2026-08-10T00:00:00Z")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/share-links")
    }

    func test_createShareLink_documents_postsToCorrectPath() async throws {
        session.stub(json: linkJSON)
        _ = try await sut.createShareLink(kind: .documents, id: "d1", role: .watcher)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/share-links")
    }

    func test_createShareLink_bodyUsesCamelCase() async throws {
        session.stub(json: linkJSON)
        _ = try await sut.createShareLink(kind: .lists, id: "l1", role: .manager, expiresAt: "2026-08-10T00:00:00Z")
        let body = bodyString()
        XCTAssertTrue(body.contains("\"role\""), "expected role, got: \(body)")
        XCTAssertTrue(body.contains("\"manager\""))
        XCTAssertTrue(body.contains("\"expiresAt\""), "expected camelCase expiresAt, got: \(body)")
        XCTAssertFalse(body.contains("expires_at"))
    }

    func test_createShareLink_nilExpiry_omitsField() async throws {
        // The camelCase encoder drops nil optionals; the backend treats an absent
        // expiresAt the same as null (no expiry), so omission is correct.
        session.stub(json: linkJSON)
        _ = try await sut.createShareLink(kind: .lists, id: "l1", role: .watcher, expiresAt: nil)
        let body = bodyString()
        XCTAssertFalse(body.contains("expiresAt"), "nil expiry should be omitted, got: \(body)")
        XCTAssertTrue(body.contains("\"role\""))
    }

    func test_createShareLink_decodesResult() async throws {
        session.stub(json: linkJSON)
        let link = try await sut.createShareLink(kind: .lists, id: "l1", role: .collaborator)
        XCTAssertEqual(link.token, "tok123")
        XCTAssertEqual(link.url, "https://interlinedlist.com/s/tok123")
    }

    func test_createShareLink_403_throwsStatus() async throws {
        session.stub(json: #"{"error":"Subscribe to share this list"}"#, statusCode: 403)
        do {
            _ = try await sut.createShareLink(kind: .lists, id: "l1", role: .watcher)
            XCTFail("Expected throw")
        } catch APIError.forbidden(let msg) {
            XCTAssertTrue(msg.contains("Subscribe"))
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        } catch APIError.server(let msg) {
            XCTAssertTrue(msg.contains("Subscribe"))
        }
    }

    // MARK: - revokeShareLink()

    func test_revokeShareLink_lists_sendsDeleteWithToken() async throws {
        session.stub(json: #"{"revoked":true}"#)
        try await sut.revokeShareLink(kind: .lists, id: "l1", token: "tok123")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/share-links/tok123")
    }

    func test_revokeShareLink_documents_sendsDeleteWithToken() async throws {
        session.stub(json: #"{"revoked":true}"#)
        try await sut.revokeShareLink(kind: .documents, id: "d1", token: "abc")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/share-links/abc")
    }

    func test_revokeShareLink_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.revokeShareLink(kind: .lists, id: "l1", token: "tok123")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: - documentCollaborators()

    func test_documentCollaborators_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"collaborators":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#)
        _ = try await sut.documentCollaborators(id: "d1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/collaborators")
    }

    func test_documentCollaborators_decodesArray() async throws {
        session.stub(json: #"{"collaborators":[\#(collaboratorJSON)],"pagination":{"total":1,"limit":20,"offset":0,"hasMore":false}}"#)
        let collaborators = try await sut.documentCollaborators(id: "d1")
        XCTAssertEqual(collaborators.count, 1)
        XCTAssertEqual(collaborators.first?.userId, "u1")
        XCTAssertEqual(collaborators.first?.collaboratorRole, .watcher)
        XCTAssertEqual(collaborators.first?.displayNameOrUsername, "Alice")
    }

    func test_documentCollaborators_missingOptionalFields_decodesNil() async throws {
        session.stub(json: #"{"collaborators":[{"userId":"u2","role":"manager"}]}"#)
        let collaborators = try await sut.documentCollaborators(id: "d1")
        XCTAssertEqual(collaborators.first?.username, nil)
        XCTAssertEqual(collaborators.first?.displayNameOrUsername, "User")
    }

    // MARK: - addDocumentCollaborator()

    func test_addDocumentCollaborator_postsToCorrectPath() async throws {
        session.stub(json: #"{"collaborator":\#(collaboratorJSON)}"#)
        _ = try await sut.addDocumentCollaborator(id: "d1", userId: "u1", role: .collaborator, notify: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/collaborators")
    }

    func test_addDocumentCollaborator_bodyUsesCamelCase() async throws {
        session.stub(json: #"{"collaborator":\#(collaboratorJSON)}"#)
        _ = try await sut.addDocumentCollaborator(id: "d1", userId: "u1", role: .collaborator, notify: true)
        let body = bodyString()
        XCTAssertTrue(body.contains("\"userId\""), "expected camelCase userId, got: \(body)")
        XCTAssertFalse(body.contains("user_id"))
        XCTAssertTrue(body.contains("\"role\""))
        XCTAssertTrue(body.contains("\"collaborator\""))
        XCTAssertTrue(body.contains("\"notify\""))
    }

    func test_addDocumentCollaborator_403_throwsStatus() async throws {
        session.stub(json: #"{"error":"Subscribe to add collaborators"}"#, statusCode: 403)
        do {
            _ = try await sut.addDocumentCollaborator(id: "d1", userId: "u1", role: .watcher)
            XCTFail("Expected throw")
        } catch APIError.forbidden(let msg) {
            XCTAssertTrue(msg.contains("Subscribe"))
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        } catch APIError.server(let msg) {
            XCTAssertTrue(msg.contains("Subscribe"))
        }
    }

    // MARK: - setDocumentCollaboratorRole()

    func test_setDocumentCollaboratorRole_sendsPutToCorrectPath() async throws {
        session.stub(json: #"{"role":"manager"}"#)
        _ = try await sut.setDocumentCollaboratorRole(id: "d1", userId: "u1", role: .manager)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/collaborators/u1")
    }

    func test_setDocumentCollaboratorRole_bodyUsesCamelCase() async throws {
        session.stub(json: #"{"role":"manager"}"#)
        _ = try await sut.setDocumentCollaboratorRole(id: "d1", userId: "u1", role: .manager, notify: true)
        let body = bodyString()
        XCTAssertTrue(body.contains("\"role\""))
        XCTAssertTrue(body.contains("\"manager\""))
        XCTAssertTrue(body.contains("\"notify\""))
    }

    func test_setDocumentCollaboratorRole_returnsRole() async throws {
        session.stub(json: #"{"role":"manager"}"#)
        let role = try await sut.setDocumentCollaboratorRole(id: "d1", userId: "u1", role: .manager)
        XCTAssertEqual(role, "manager")
    }

    // MARK: - removeDocumentCollaborator()

    func test_removeDocumentCollaborator_sendsDeleteToCorrectPath() async throws {
        session.stub(json: #"{"removed":true}"#)
        try await sut.removeDocumentCollaborator(id: "d1", userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/collaborators/u1")
    }

    // MARK: - searchDocumentCollaboratorCandidates()

    func test_searchDocumentCollaboratorCandidates_sendsGetWithQuery() async throws {
        session.stub(json: #"{"users":[]}"#)
        _ = try await sut.searchDocumentCollaboratorCandidates(id: "d1", query: "alice smith")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/d1/collaborators/users")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("q=alice%20smith") || url.contains("q=alice+smith"), "expected percent-encoded query, got: \(url)")
    }

    func test_searchDocumentCollaboratorCandidates_decodesUsers() async throws {
        session.stub(json: #"{"users":[{"id":"u1","username":"alice","displayName":"Alice","email":"a@b.co","avatar":null}]}"#)
        let users = try await sut.searchDocumentCollaboratorCandidates(id: "d1", query: "al")
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, "u1")
    }
}
