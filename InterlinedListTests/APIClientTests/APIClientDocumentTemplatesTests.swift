import XCTest
@testable import InterlinedList

final class APIClientDocumentTemplatesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

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

    // MARK: documentTemplates()

    func test_documentTemplates_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"folderCreated":false,"templatesFolderId":"tf","templates":[]}"#)
        _ = try await sut.documentTemplates()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/templates")
    }

    func test_documentTemplates_sendsBearerToken() async throws {
        session.stub(json: #"{"templates":[]}"#)
        _ = try await sut.documentTemplates()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_documentTemplates_decodesTemplates() async throws {
        session.stub(json: #"""
        {"folderCreated":true,"templatesFolderId":"tf","templates":[
          {"id":"t1","title":"Weekly Notes","relativePath":"notes/weekly"},
          {"id":"t2","title":"Meeting","relativePath":null}
        ]}
        """#)
        let templates = try await sut.documentTemplates()
        XCTAssertEqual(templates.count, 2)
        XCTAssertEqual(templates.first?.id, "t1")
        XCTAssertEqual(templates.first?.title, "Weekly Notes")
        XCTAssertEqual(templates.first?.relativePath, "notes/weekly")
        XCTAssertNil(templates.last?.relativePath)
    }

    func test_documentTemplates_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.documentTemplates()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: createDocumentFromTemplate()

    func test_createFromTemplate_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"document":{"id":"d9","title":"Copy"}}"#, statusCode: 201)
        _ = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: "f2")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/from-template")
    }

    func test_createFromTemplate_usesCamelCaseBodyKeys() async throws {
        session.stub(json: #"{"document":{"id":"d9","title":"Copy"}}"#, statusCode: 201)
        _ = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: "f2")
        let body = bodyString()
        XCTAssertTrue(body.contains("\"templateDocumentId\""), "camelCase key missing: \(body)")
        XCTAssertTrue(body.contains("\"targetFolderId\""), "camelCase key missing: \(body)")
        XCTAssertFalse(body.contains("template_document_id"))
        XCTAssertFalse(body.contains("target_folder_id"))
    }

    func test_createFromTemplate_nilFolder_omitsTargetFolderId() async throws {
        session.stub(json: #"{"document":{"id":"d9","title":"Copy"}}"#, statusCode: 201)
        _ = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: nil)
        let body = bodyString()
        XCTAssertTrue(body.contains("\"templateDocumentId\""))
        XCTAssertFalse(body.contains("targetFolderId"), "nil folder should omit the key: \(body)")
    }

    func test_createFromTemplate_decodesWrappedDocument() async throws {
        session.stub(json: #"{"message":"ok","document":{"id":"d9","title":"Copy","content":"hi"}}"#, statusCode: 201)
        let doc = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: nil)
        XCTAssertEqual(doc.id, "d9")
        XCTAssertEqual(doc.title, "Copy")
        XCTAssertEqual(doc.content, "hi")
    }

    func test_createFromTemplate_decodesBareDocument() async throws {
        session.stub(json: #"{"id":"d10","title":"Bare"}"#, statusCode: 201)
        let doc = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: nil)
        XCTAssertEqual(doc.id, "d10")
        XCTAssertEqual(doc.title, "Bare")
    }

    func test_createFromTemplate_403_throwsStatusError() async throws {
        session.stub(json: #"{"error":"Subscribe to create documents."}"#, statusCode: 403)
        do {
            _ = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        } catch APIError.server(let msg) {
            // The client surfaces the {"error":...} body when present; accept either shape
            // so the test asserts the subscriber gate is rejected, not the exact error type.
            XCTAssertEqual(msg, "Subscribe to create documents.")
        }
    }

    func test_createFromTemplate_403_withoutErrorBody_throwsStatus403() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.createDocumentFromTemplate(templateDocumentId: "t1", targetFolderId: nil)
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }
}
