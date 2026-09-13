import XCTest
@testable import InterlinedList

final class APIClientDocumentsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let docJSON = #"{"id":"d1","title":"My Doc"}"#
    private let folderJSON = #"{"id":"f1","name":"Folder"}"#
    private let renamedFolderJSON = #"{"id":"f1","name":"Renamed","parentId":"f2"}"#

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

    // MARK: documents()

    func test_documents_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"documents":[]}"#)
        _ = try await sut.documents()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents")
    }

    func test_documents_withFolderId_usesFolderScopedPath() async throws {
        // `GET /api/documents` ignores a folderId query and returns root docs, so a folder's
        // contents must come from the folder-scoped endpoint.
        session.stub(json: #"{"documents":[]}"#)
        _ = try await sut.documents(folderId: "f1")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/folders/f1/documents")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertFalse(url.contains("folderId="))
    }

    func test_documents_emptyFolderId_usesRootPath() async throws {
        session.stub(json: #"{"documents":[]}"#)
        _ = try await sut.documents(folderId: "")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents")
    }

    func test_documents_decodesResult() async throws {
        session.stub(json: #"{"documents":[\#(docJSON)]}"#)
        let docs = try await sut.documents()
        XCTAssertEqual(docs.count, 1)
        XCTAssertEqual(docs.first?.id, "d1")
    }

    func test_documents_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.documents()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: createDocument()

    func test_createDocument_root_sendsPostToDocumentsPath() async throws {
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.createDocument(title: "Doc", content: nil, isPublic: false, folderId: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents")
    }

    func test_createDocument_withFolderId_postsToFolderScopedPath() async throws {
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.createDocument(title: "Doc", content: nil, isPublic: true, folderId: "f1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/folders/f1/documents")
    }

    func test_createDocument_bodyUsesCamelCaseAndNoFolderField() async throws {
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.createDocument(title: "Doc", content: "x", isPublic: true, folderId: "f1")
        let body = bodyString()
        XCTAssertTrue(body.contains("\"isPublic\""), "expected camelCase isPublic, got: \(body)")
        XCTAssertFalse(body.contains("is_public"), "snake_case isPublic is dropped server-side")
        // Folder is conveyed by the path; the body must not carry a folder field.
        XCTAssertFalse(body.contains("folderId"))
        XCTAssertFalse(body.contains("folder_id"))
    }

    // MARK: updateDocument()

    func test_updateDocument_sendsPatchToCorrectPath() async throws {
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "New", content: nil, isPublic: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/documents/d1") == true)
    }

    func test_updateDocument_bodyUsesCamelCase() async throws {
        session.stub(json: #"{"document":\#(docJSON)}"#)
        _ = try await sut.updateDocument(id: "d1", title: "New", content: nil, isPublic: true, folderId: "f1")
        let body = bodyString()
        XCTAssertTrue(body.contains("\"folderId\""), "expected camelCase folderId, got: \(body)")
        XCTAssertTrue(body.contains("\"isPublic\""))
        XCTAssertFalse(body.contains("folder_id"))
        XCTAssertFalse(body.contains("is_public"))
    }

    // MARK: deleteDocument()

    func test_deleteDocument_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.deleteDocument(id: "d1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/documents/d1") == true)
    }

    // MARK: documentFolders()

    func test_documentFolders_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"folders":[\#(folderJSON)]}"#)
        let folders = try await sut.documentFolders()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/folders")
        XCTAssertEqual(folders.count, 1)
    }

    // MARK: createDocumentFolder()

    func test_createDocumentFolder_sendsPostWithName() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        let folder = try await sut.createDocumentFolder(name: "Folder", parentId: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(folder.name, "Folder")
    }

    func test_createDocumentFolder_nested_bodyUsesCamelCaseParentId() async throws {
        session.stub(json: #"{"folder":\#(folderJSON)}"#)
        _ = try await sut.createDocumentFolder(name: "Sub", parentId: "f1")
        let body = bodyString()
        XCTAssertTrue(body.contains("\"parentId\""), "expected camelCase parentId, got: \(body)")
        XCTAssertFalse(body.contains("parent_id"))
    }

    // MARK: deleteDocumentFolder()

    func test_deleteDocumentFolder_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.deleteDocumentFolder(id: "f1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/folders/f1")
    }

    func test_deleteDocumentFolder_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            try await sut.deleteDocumentFolder(id: "f1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: updateDocumentFolder()

    func test_updateDocumentFolder_sendsPutToFolderPath() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        let folder = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/folders/f1")
        XCTAssertEqual(folder.name, "Renamed")
    }

    func test_updateDocumentFolder_pathScoped_noFolderIdQuery() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
        let url = session.lastRequest?.url?.absoluteString ?? ""
        XCTAssertFalse(url.contains("folderId="), "folder routes are path-scoped, got: \(url)")
        XCTAssertFalse(url.contains("?"), "expected no query, got: \(url)")
    }

    func test_updateDocumentFolder_encodesIdIntoPath() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f 1", name: "Renamed")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/folders/f 1")
    }

    func test_updateDocumentFolder_bodyUsesCamelCaseName() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
        let body = bodyString()
        XCTAssertEqual(body, #"{"name":"Renamed"}"#)
    }

    /// A rename must not carry `parentId` at all: the route validates (and moves)
    /// whenever the key is present, so a stray `null` would silently move the
    /// folder to the root.
    func test_updateDocumentFolder_rename_omitsParentId() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
        XCTAssertFalse(bodyString().contains("parentId"))
        XCTAssertFalse(bodyString().contains("parent_id"))
    }

    func test_updateDocumentFolder_moveToFolder_sendsCamelCaseParentId() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f1", parentId: .folder("f2"))
        let body = bodyString()
        XCTAssertEqual(body, #"{"parentId":"f2"}"#)
        XCTAssertFalse(body.contains("parent_id"))
    }

    /// Moving to the root needs an explicit `null` — Swift's synthesized
    /// `Encodable` would drop a `nil` optional and the move would never happen.
    func test_updateDocumentFolder_moveToRoot_sendsExplicitNull() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f1", parentId: .root)
        XCTAssertEqual(bodyString(), #"{"parentId":null}"#)
    }

    func test_updateDocumentFolder_renameAndMove_sendsBothKeys() async throws {
        session.stub(json: #"{"folder":\#(renamedFolderJSON)}"#)
        _ = try await sut.updateDocumentFolder(id: "f1", name: "Renamed", parentId: .folder("f2"))
        let body = bodyString()
        XCTAssertTrue(body.contains(#""name":"Renamed""#), body)
        XCTAssertTrue(body.contains(#""parentId":"f2""#), body)
    }

    func test_updateDocumentFolder_decodesSavedFolder() async throws {
        session.stub(json: #"{"message":"Folder updated successfully","folder":\#(renamedFolderJSON)}"#)
        let folder = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
        XCTAssertEqual(folder.id, "f1")
        XCTAssertEqual(folder.name, "Renamed")
        XCTAssertEqual(folder.parentId, "f2")
    }

    /// The server rejects a circular move with a 400 whose body carries readable
    /// text; `checkResponse` surfaces it as `.server` so the view can show it.
    func test_updateDocumentFolder_cycle400_throwsServerMessage() async throws {
        session.stub(json: #"{"error":"Setting this parent would create a circular reference","code":"bad_request"}"#,
                     statusCode: 400)
        do {
            _ = try await sut.updateDocumentFolder(id: "f1", parentId: .folder("f1child"))
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "Setting this parent would create a circular reference")
        }
    }

    func test_updateDocumentFolder_duplicateName409_throwsServerMessage() async throws {
        session.stub(json: #"{"error":"A folder with that name already exists here","code":"conflict"}"#,
                     statusCode: 409)
        do {
            _ = try await sut.updateDocumentFolder(id: "f1", name: "Taken")
            XCTFail("Expected throw")
        } catch APIError.server(let message) {
            XCTAssertEqual(message, "A folder with that name already exists here")
        }
    }

    func test_updateDocumentFolder_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_updateDocumentFolder_missingFolderInResponse_throwsNoData() async throws {
        session.stub(json: #"{"message":"Folder updated successfully"}"#)
        do {
            _ = try await sut.updateDocumentFolder(id: "f1", name: "Renamed")
            XCTFail("Expected throw")
        } catch APIError.noData {
        }
    }
}
