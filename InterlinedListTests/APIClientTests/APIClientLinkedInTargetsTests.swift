import XCTest
@testable import InterlinedList

final class APIClientLinkedInTargetsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let fullTargetsJSON = #"""
    {
      "targets": [
        { "kind": "personal", "label": "Jane Doe", "avatarUrl": "https://cdn/a.jpg", "pageId": null, "personalPageId": null, "linkedInPageId": null, "enabled": true },
        { "kind": "orgPage", "label": "Acme Inc", "avatarUrl": null, "pageId": "page-1", "personalPageId": null, "linkedInPageId": "urn:li:org:1", "enabled": true },
        { "kind": "personalPage", "label": "Side Co", "avatarUrl": null, "pageId": null, "personalPageId": "pp-9", "linkedInPageId": "urn:li:org:9", "enabled": false }
      ],
      "orgScopeMissing": false
    }
    """#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: linkedInPostingTargets

    func test_linkedInPostingTargets_sendsGetToCorrectPathWithBearer() async throws {
        session.stub(json: fullTargetsJSON)
        _ = try await sut.linkedInPostingTargets()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/linkedin/posting-targets")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_linkedInPostingTargets_decodesAllVariants() async throws {
        session.stub(json: fullTargetsJSON)
        let targets = try await sut.linkedInPostingTargets()
        XCTAssertEqual(targets.count, 3)

        let personal = targets[0]
        XCTAssertEqual(personal.kind, "personal")
        XCTAssertEqual(personal.label, "Jane Doe")
        XCTAssertEqual(personal.avatarUrl, "https://cdn/a.jpg")
        XCTAssertNil(personal.pageId)
        XCTAssertNil(personal.personalPageId)
        XCTAssertTrue(personal.enabled)

        let org = targets[1]
        XCTAssertEqual(org.kind, "orgPage")
        XCTAssertEqual(org.pageId, "page-1")
        XCTAssertEqual(org.linkedInPageId, "urn:li:org:1")
        XCTAssertNil(org.avatarUrl)

        let personalPage = targets[2]
        XCTAssertEqual(personalPage.kind, "personalPage")
        XCTAssertEqual(personalPage.personalPageId, "pp-9")
        XCTAssertFalse(personalPage.enabled)
    }

    func test_linkedInPostingTargets_tolerantOfMissingOptionalFields() async throws {
        session.stub(json: #"{"targets":[{"kind":"personal","label":"Me","enabled":true}]}"#)
        let targets = try await sut.linkedInPostingTargets()
        XCTAssertEqual(targets.count, 1)
        let t = targets[0]
        XCTAssertEqual(t.kind, "personal")
        XCTAssertNil(t.avatarUrl)
        XCTAssertNil(t.pageId)
        XCTAssertNil(t.personalPageId)
        XCTAssertNil(t.linkedInPageId)
    }

    func test_linkedInPostingTargets_missingTargetsKey_returnsEmpty() async throws {
        session.stub(json: #"{"orgScopeMissing":true}"#)
        let targets = try await sut.linkedInPostingTargets()
        XCTAssertTrue(targets.isEmpty)
    }

    func test_linkedInPostingTargets_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.linkedInPostingTargets()
            XCTFail("Expected APIError.status(401)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    func test_linkedInPostingTargets_403_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 403)
        do {
            _ = try await sut.linkedInPostingTargets()
            XCTFail("Expected APIError.status(403)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 403)
        }
    }

    func test_linkedInPostingTargets_500_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 500)
        do {
            _ = try await sut.linkedInPostingTargets()
            XCTFail("Expected APIError.status(500)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 500)
        }
    }
}
