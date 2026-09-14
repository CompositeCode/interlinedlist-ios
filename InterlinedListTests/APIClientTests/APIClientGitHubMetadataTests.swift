import XCTest
@testable import InterlinedList

/// `githubLabels` / `githubAssignees` / `githubOrgs` / `githubNextIssueNumber` —
/// the repo-metadata routes that back the label and assignee pickers.
final class APIClientGitHubMetadataTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: - Labels

    private let labelsJSON = """
    [
      {"id":1,"node_id":"n1","name":"bug","color":"d73a4a","description":"Something is broken","default":true},
      {"id":2,"node_id":"n2","name":"good first issue","color":"7057ff"}
    ]
    """

    func test_githubLabels_sendsGetToCorrectPath() async throws {
        session.stub(json: labelsJSON)
        _ = try await sut.githubLabels(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/github/repos/octocat/Hello-World/labels")
    }

    func test_githubLabels_sendsBearerToken() async throws {
        session.stub(json: labelsJSON)
        _ = try await sut.githubLabels(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    /// Raw GitHub JSON, so the response is a bare array with snake_case keys and
    /// extra fields the client doesn't model.
    func test_githubLabels_decodesBareArrayAndIgnoresUnknownFields() async throws {
        session.stub(json: labelsJSON)
        let labels = try await sut.githubLabels(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(labels.map(\.name), ["bug", "good first issue"])
        XCTAssertEqual(labels[0].color, "d73a4a")
        XCTAssertEqual(labels[0].description, "Something is broken")
        XCTAssertNil(labels[1].description)
    }

    // MARK: - Assignees

    private let assigneesJSON = """
    [
      {"login":"adron","id":7,"avatar_url":"https://example.com/a.png","type":"User"},
      {"login":"octocat","id":8}
    ]
    """

    func test_githubAssignees_sendsGetToCorrectPath() async throws {
        session.stub(json: assigneesJSON)
        _ = try await sut.githubAssignees(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/github/repos/octocat/Hello-World/assignees")
    }

    /// `avatar_url` must arrive as `avatarUrl` via `convertFromSnakeCase`.
    func test_githubAssignees_decodesLoginAndAvatar() async throws {
        session.stub(json: assigneesJSON)
        let assignees = try await sut.githubAssignees(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(assignees.map(\.login), ["adron", "octocat"])
        XCTAssertEqual(assignees[0].avatarUrl, "https://example.com/a.png")
        XCTAssertNil(assignees[1].avatarUrl)
    }

    // MARK: - Orgs (two observed response shapes)

    func test_githubOrgs_decodesBareArray() async throws {
        session.stub(json: #"[{"login":"acme","avatar_url":"https://example.com/o.png"},{"login":"widgets"}]"#)
        let orgs = try await sut.githubOrgs()
        XCTAssertEqual(orgs.map(\.login), ["acme", "widgets"])
        XCTAssertEqual(orgs[0].avatarUrl, "https://example.com/o.png")
    }

    func test_githubOrgs_decodesEnvelope() async throws {
        session.stub(json: #"{"orgs":[{"login":"acme","avatar_url":null}]}"#)
        let orgs = try await sut.githubOrgs()
        XCTAssertEqual(orgs.map(\.login), ["acme"])
        XCTAssertNil(orgs[0].avatarUrl)
    }

    func test_githubOrgs_emptyArrayIsNotAnError() async throws {
        session.stub(json: "[]")
        let orgs = try await sut.githubOrgs()
        XCTAssertTrue(orgs.isEmpty)
    }

    func test_githubOrgs_sendsGetToCorrectPath() async throws {
        session.stub(json: "[]")
        _ = try await sut.githubOrgs()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/github/orgs")
    }

    // MARK: - Next issue number

    func test_githubNextIssueNumber_decodesNextNumber() async throws {
        session.stub(json: #"{"nextNumber":42}"#)
        let next = try await sut.githubNextIssueNumber(owner: "octocat", repo: "Hello-World")
        XCTAssertEqual(next, 42)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/github/repos/octocat/Hello-World/next-issue-number")
    }

    // MARK: - Not-linked path

    /// These routes answer **400** — not 401 — when no GitHub identity is linked,
    /// so callers must not treat it as a session failure.
    func test_githubLabels_400NotLinked_throwsWithoutUnauthorized() async throws {
        session.stub(json: #"{"error":"GitHub account not linked"}"#, statusCode: 400)
        do {
            _ = try await sut.githubLabels(owner: "octocat", repo: "Hello-World")
            XCTFail("expected a throw")
        } catch APIError.status(401) {
            XCTFail("400 must not surface as a 401")
        } catch {
            // expected
        }
    }
}
