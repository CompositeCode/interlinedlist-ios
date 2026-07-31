import XCTest
@testable import InterlinedList

final class APIClientGitHubTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: - githubRepos()

    private let reposJSON = """
    [
      {"full_name":"octocat/Hello-World","name":"Hello-World","private":false,"owner":{"login":"octocat"}},
      {"full_name":"acme/secret-repo","name":"secret-repo","private":true,"owner":{"login":"acme"}}
    ]
    """

    func test_githubRepos_sendsGetToCorrectPath() async throws {
        session.stub(json: reposJSON)
        _ = try await sut.githubRepos()
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/github/repos")
    }

    func test_githubRepos_sendsBearerToken() async throws {
        session.stub(json: reposJSON)
        _ = try await sut.githubRepos()
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_githubRepos_decodesFullNameIsPrivateOwnerLogin() async throws {
        session.stub(json: reposJSON)
        let repos = try await sut.githubRepos()
        XCTAssertEqual(repos.count, 2)
        let first = try XCTUnwrap(repos.first)
        XCTAssertEqual(first.fullName, "octocat/Hello-World")
        XCTAssertEqual(first.name, "Hello-World")
        XCTAssertEqual(first.isPrivate, false)
        XCTAssertEqual(first.ownerLogin, "octocat")
        XCTAssertEqual(repos[1].isPrivate, true)
        XCTAssertEqual(repos[1].ownerLogin, "acme")
    }

    func test_githubRepos_tolerantOfMissingOptionalFields() async throws {
        // Only full_name present — name/private/owner absent.
        session.stub(json: #"[{"full_name":"solo/repo"}]"#)
        let repos = try await sut.githubRepos()
        let repo = try XCTUnwrap(repos.first)
        XCTAssertEqual(repo.fullName, "solo/repo")
        XCTAssertNil(repo.name)
        XCTAssertNil(repo.isPrivate)
        XCTAssertNil(repo.ownerLogin)
        // Derived accessors still work off full_name.
        XCTAssertEqual(repo.owner, "solo")
        XCTAssertEqual(repo.repo, "repo")
    }

    func test_githubRepos_400NotLinked_throwsServer() async throws {
        session.stub(json: #"{"error":"GitHub account not linked"}"#, statusCode: 400)
        do {
            _ = try await sut.githubRepos()
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "GitHub account not linked")
        }
    }

    func test_githubRepos_400WithoutErrorBody_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 400)
        do {
            _ = try await sut.githubRepos()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 400)
        }
    }

    func test_githubRepos_401_throwsStatus() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.githubRepos()
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: - githubIssues()

    func test_githubIssues_sendsRepoAndStateQuery() async throws {
        session.stub(json: #"[{"number":1,"title":"Bug","state":"open","html_url":"https://github.com/o/r/issues/1"}]"#)
        let issues = try await sut.githubIssues(repo: "octocat/Hello-World", state: "open")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/github/issues")
        let query = session.lastRequest?.url?.query ?? ""
        XCTAssertTrue(query.contains("repo=octocat/Hello-World") || query.contains("repo=octocat%2FHello-World"))
        XCTAssertTrue(query.contains("state=open"))
        XCTAssertEqual(issues.first?.number, 1)
        XCTAssertEqual(issues.first?.title, "Bug")
        XCTAssertEqual(issues.first?.htmlUrl, "https://github.com/o/r/issues/1")
    }

    // MARK: - refreshList()

    func test_refreshList_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"message":"Refreshed","count":3}"#)
        try await sut.refreshList(id: "l1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/lists/l1/refresh")
    }

    func test_refreshList_sendsBearerToken() async throws {
        session.stub(json: #"{"message":"Refreshed"}"#)
        try await sut.refreshList(id: "l1")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func test_refreshList_400NotGitHub_throwsServer() async throws {
        session.stub(json: #"{"error":"Refresh is only available for GitHub-backed lists"}"#, statusCode: 400)
        do {
            try await sut.refreshList(id: "l1")
            XCTFail("Expected throw")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "Refresh is only available for GitHub-backed lists")
        }
    }

    // MARK: - createList() with githubSource

    private let listJSON = #"{"id":"gh1","title":"Issues","source":"github","githubRepo":"octocat/Hello-World","created_at":"2024-01-01T00:00:00Z"}"#

    func test_createList_withGitHubSource_sendsGitHubSourceObject() async throws {
        session.stub(json: #"{"data":\#(listJSON),"refreshStatus":"pending"}"#)
        _ = try await sut.createList(
            title: "Issues",
            description: nil,
            isPublic: true,
            githubSource: APIClient.GitHubSource(owner: "octocat", repo: "Hello-World")
        )
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        let source = try XCTUnwrap(json["githubSource"] as? [String: Any],
                                   "githubSource must be an object with owner/repo")
        XCTAssertEqual(source["owner"] as? String, "octocat")
        XCTAssertEqual(source["repo"] as? String, "Hello-World")
        XCTAssertNil(json["schema"], "GitHub-backed create must not send a DSL schema")
    }

    func test_createList_withGitHubSource_decodesGitHubList() async throws {
        session.stub(json: #"{"data":\#(listJSON),"refreshStatus":"pending"}"#)
        let list = try await sut.createList(
            title: "Issues",
            description: nil,
            isPublic: true,
            githubSource: APIClient.GitHubSource(owner: "octocat", repo: "Hello-World")
        )
        XCTAssertEqual(list.source, "github")
        XCTAssertEqual(list.githubRepo, "octocat/Hello-World")
        XCTAssertTrue(list.isGitHubBacked)
    }

    func test_createList_localList_stillSendsDSLObjectAndNoGitHubSource() async throws {
        session.stub(json: #"{"data":{"id":"l2","title":"Books","created_at":"2024-01-01T00:00:00Z"}}"#)
        let schema = ListSchemaDSL(name: "Books", description: nil, fields: [
            .init(key: "title", label: "Title", type: "text", displayOrder: 0, required: false, visible: true),
        ])
        _ = try await sut.createList(title: "Books", description: nil, isPublic: true, schema: schema)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try? JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["githubSource"], "Local list must not send githubSource")
        let sentSchema = try XCTUnwrap(json["schema"] as? [String: Any],
                                       "Local list must still send the DSL schema object")
        XCTAssertEqual(sentSchema["name"] as? String, "Books")
        let fields = try XCTUnwrap(sentSchema["fields"] as? [[String: Any]])
        XCTAssertEqual(fields.first?["key"] as? String, "title")
    }
}
