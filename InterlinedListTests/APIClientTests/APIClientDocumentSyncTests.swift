import XCTest
@testable import InterlinedList

final class APIClientDocumentSyncTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    func test_documentSync_noCursor_sendsGetToBarePath() async throws {
        session.stub(json: #"{"folders":[],"documents":[],"lastSyncAt":"2026-07-31T00:00:00Z"}"#)
        _ = try await sut.documentSync()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/sync")
        XCTAssertNil(session.lastRequest?.url?.query)
    }

    func test_documentSync_emptyCursor_omitsQuery() async throws {
        session.stub(json: #"{"folders":[],"documents":[]}"#)
        _ = try await sut.documentSync(lastSyncAt: "")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/sync")
        XCTAssertNil(session.lastRequest?.url?.query)
    }

    func test_documentSync_withCursor_appendsQueryThatRoundTrips() async throws {
        session.stub(json: #"{"folders":[],"documents":[]}"#)
        let cursor = "2026-07-31T12:34:56Z"
        _ = try await sut.documentSync(lastSyncAt: cursor)
        let url = session.lastRequest?.url
        XCTAssertEqual(url?.path, "/api/documents/sync")
        // The cursor round-trips: URLComponents leaves `:` unescaped in the query
        // (it is query-allowed per RFC 3986), so the value parses back to the original.
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "lastSyncAt" })?.value, cursor)
    }

    func test_documentSync_cursorWithReservedChars_isPercentEncoded() async throws {
        session.stub(json: #"{"folders":[],"documents":[]}"#)
        // A value containing `&`/`=` must be escaped so it can't split the query.
        let cursor = "a&b=c"
        _ = try await sut.documentSync(lastSyncAt: cursor)
        let url = session.lastRequest?.url
        let raw = url?.absoluteString ?? ""
        XCTAssertFalse(raw.contains("lastSyncAt=a&b=c"), "reserved chars must be escaped: \(raw)")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "lastSyncAt" })?.value, cursor)
    }

    func test_documentSync_sendsAuthorizationHeader() async throws {
        session.stub(json: #"{"folders":[],"documents":[]}"#)
        _ = try await sut.documentSync()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_documentSync_decodesFoldersDocumentsAndCursor() async throws {
        let json = #"""
        {
          "folders": [{"id":"f1","name":"Projects","parentId":null,"updatedAt":"2026-07-30T00:00:00Z"}],
          "documents": [{"id":"d1","folderId":"f1","title":"Notes","content":"# Hi","isPublic":false,"updatedAt":"2026-07-30T00:00:00Z"}],
          "lastSyncAt": "2026-07-31T00:00:00Z"
        }
        """#
        session.stub(json: json)
        let resp = try await sut.documentSync()
        XCTAssertEqual(resp.folders.count, 1)
        XCTAssertEqual(resp.folders.first?.id, "f1")
        XCTAssertEqual(resp.folders.first?.name, "Projects")
        XCTAssertEqual(resp.documents.count, 1)
        XCTAssertEqual(resp.documents.first?.id, "d1")
        XCTAssertEqual(resp.documents.first?.folderId, "f1")
        XCTAssertEqual(resp.lastSyncAt, "2026-07-31T00:00:00Z")
    }

    func test_documentSync_toleratesTombstonedRows() async throws {
        let json = #"""
        {
          "folders": [{"id":"f1","name":"Old","deletedAt":"2026-07-31T00:00:00Z"}],
          "documents": [{"id":"d1","title":"Gone","deletedAt":"2026-07-31T00:00:00Z"}],
          "lastSyncAt": "2026-07-31T00:00:00Z"
        }
        """#
        session.stub(json: json)
        let resp = try await sut.documentSync(lastSyncAt: "2026-07-30T00:00:00Z")
        XCTAssertEqual(resp.folders.first?.deletedAt, "2026-07-31T00:00:00Z")
        XCTAssertEqual(resp.documents.first?.deletedAt, "2026-07-31T00:00:00Z")
    }

    func test_documentSync_missingArrays_decodeAsEmpty() async throws {
        session.stub(json: #"{"lastSyncAt":"2026-07-31T00:00:00Z"}"#)
        let resp = try await sut.documentSync()
        XCTAssertTrue(resp.folders.isEmpty)
        XCTAssertTrue(resp.documents.isEmpty)
        XCTAssertEqual(resp.lastSyncAt, "2026-07-31T00:00:00Z")
    }

    func test_documentSync_401_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.documentSync()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_documentSync_429_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 429)
        do {
            _ = try await sut.documentSync(lastSyncAt: "2026-07-30T00:00:00Z")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 429)
        }
    }

    // MARK: - pushDocumentSync (Slice 2)

    private func opsBody(from request: URLRequest?) throws -> [[String: Any]] {
        let body = try XCTUnwrap(request?.httpBody)
        let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return try XCTUnwrap(obj?["operations"] as? [[String: Any]])
    }

    func test_pushDocumentSync_postsToSyncPath() async throws {
        session.stub(json: #"{"lastSyncAt":"2026-08-01T00:00:00Z"}"#)
        _ = try await sut.pushDocumentSync(operations: [
            SyncOperation(op: .create, type: .document, data: SyncOpData(id: "d1", title: "T"))
        ])
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/documents/sync")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_pushDocumentSync_returnsLastSyncAt() async throws {
        session.stub(json: #"{"lastSyncAt":"2026-08-01T12:00:00Z"}"#)
        let cursor = try await sut.pushDocumentSync(operations: [
            SyncOperation(op: .update, type: .document, data: SyncOpData(id: "d1", title: "T"))
        ])
        XCTAssertEqual(cursor, "2026-08-01T12:00:00Z")
    }

    func test_pushDocumentSync_bodyIsCamelCaseOperationsArray() async throws {
        session.stub(json: #"{"lastSyncAt":"c"}"#)
        _ = try await sut.pushDocumentSync(operations: [
            SyncOperation(op: .create, type: .document,
                          data: SyncOpData(id: "d1", folderId: "f1", title: "Notes",
                                           content: "# Hi", isPublic: true))
        ])
        let ops = try opsBody(from: session.lastRequest)
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops[0]["op"] as? String, "create")
        XCTAssertEqual(ops[0]["type"] as? String, "document")
        let data = try XCTUnwrap(ops[0]["data"] as? [String: Any])
        XCTAssertEqual(data["id"] as? String, "d1")
        XCTAssertEqual(data["folderId"] as? String, "f1")
        XCTAssertEqual(data["title"] as? String, "Notes")
        XCTAssertEqual(data["isPublic"] as? Bool, true)
    }

    func test_pushDocumentSync_deleteOp_carriesOnlyId() async throws {
        session.stub(json: #"{"lastSyncAt":"c"}"#)
        _ = try await sut.pushDocumentSync(operations: [
            SyncOperation(op: .delete, type: .document, data: SyncOpData(id: "d9"))
        ])
        let ops = try opsBody(from: session.lastRequest)
        XCTAssertEqual(ops[0]["op"] as? String, "delete")
        let data = try XCTUnwrap(ops[0]["data"] as? [String: Any])
        XCTAssertEqual(data.keys.sorted(), ["id"])
        XCTAssertEqual(data["id"] as? String, "d9")
    }

    func test_pushDocumentSync_429_throwsRateLimited() async throws {
        session.stub(data: Data(), statusCode: 429)
        do {
            _ = try await sut.pushDocumentSync(operations: [
                SyncOperation(op: .create, type: .document, data: SyncOpData(id: "d1", title: "T"))
            ])
            XCTFail("Expected rateLimited")
        } catch APIError.rateLimited {
            // expected — distinct retryable error, not a hard .status(429)
        }
    }

    func test_pushDocumentSync_401_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.pushDocumentSync(operations: [
                SyncOperation(op: .create, type: .document, data: SyncOpData(id: "d1", title: "T"))
            ])
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_pushDocumentSync_missingCursor_throwsNoData() async throws {
        session.stub(json: #"{}"#)
        do {
            _ = try await sut.pushDocumentSync(operations: [
                SyncOperation(op: .create, type: .document, data: SyncOpData(id: "d1", title: "T"))
            ])
            XCTFail("Expected noData")
        } catch APIError.noData {
            // expected
        }
    }
}
