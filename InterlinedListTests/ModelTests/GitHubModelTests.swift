import XCTest
@testable import InterlinedList

final class GitHubRepoCodableTests: XCTestCase {
    // GitHubRepo is only ever decoded via APIClient's convertFromSnakeCase decoder,
    // which rewrites full_name → fullName before CodingKeys match. Mirror that here.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let json = #"{"full_name":"octocat/Hello-World","name":"Hello-World","private":true,"owner":{"login":"octocat"}}"#

    func test_decode_mapsSnakeCaseFields() throws {
        let repo = try decoder.decode(GitHubRepo.self, from: Data(json.utf8))
        XCTAssertEqual(repo.fullName, "octocat/Hello-World")
        XCTAssertEqual(repo.name, "Hello-World")
        XCTAssertEqual(repo.isPrivate, true)
        XCTAssertEqual(repo.ownerLogin, "octocat")
    }

    func test_decode_missingOptionalFields_isNil() throws {
        let repo = try decoder.decode(GitHubRepo.self, from: Data(#"{"full_name":"solo/repo"}"#.utf8))
        XCTAssertEqual(repo.fullName, "solo/repo")
        XCTAssertNil(repo.name)
        XCTAssertNil(repo.isPrivate)
        XCTAssertNil(repo.ownerLogin)
    }

    func test_id_isFullName() {
        let repo = GitHubRepo(fullName: "a/b", name: nil, isPrivate: nil, ownerLogin: nil)
        XCTAssertEqual(repo.id, "a/b")
    }

    func test_ownerAndRepo_derivedFromFullName_whenFieldsAbsent() {
        let repo = GitHubRepo(fullName: "octocat/Hello-World", name: nil, isPrivate: nil, ownerLogin: nil)
        XCTAssertEqual(repo.owner, "octocat")
        XCTAssertEqual(repo.repo, "Hello-World")
    }

    func test_ownerAndRepo_preferExplicitFields() {
        let repo = GitHubRepo(fullName: "octocat/Hello-World", name: "Hello-World", isPrivate: nil, ownerLogin: "octocat")
        XCTAssertEqual(repo.owner, "octocat")
        XCTAssertEqual(repo.repo, "Hello-World")
    }
}

final class GitHubIssueCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_mapsHtmlUrl() throws {
        let json = #"{"number":42,"title":"Fix crash","state":"open","html_url":"https://github.com/o/r/issues/42"}"#
        let issue = try decoder.decode(GitHubIssue.self, from: Data(json.utf8))
        XCTAssertEqual(issue.number, 42)
        XCTAssertEqual(issue.title, "Fix crash")
        XCTAssertEqual(issue.state, "open")
        XCTAssertEqual(issue.htmlUrl, "https://github.com/o/r/issues/42")
        XCTAssertEqual(issue.id, 42)
    }

    func test_decode_missingOptionalFields() throws {
        let issue = try decoder.decode(GitHubIssue.self, from: Data(#"{"number":1,"title":"x"}"#.utf8))
        XCTAssertNil(issue.state)
        XCTAssertNil(issue.htmlUrl)
    }
}

final class UserListGitHubFieldsTests: XCTestCase {
    // UserList declares explicit CodingKeys, so github fields arrive camelCase.
    private let decoder = JSONDecoder()

    func test_decode_localList_hasNilGitHubFields() throws {
        let json = #"{"id":"1","title":"Books","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertNil(list.source)
        XCTAssertNil(list.githubRepo)
        XCTAssertNil(list.githubMeta)
        XCTAssertFalse(list.isGitHubBacked)
    }

    func test_decode_gitHubList_withMeta() throws {
        let json = """
        {
          "id":"gh1","title":"Issues","createdAt":"2024-01-01T00:00:00Z",
          "source":"github","githubRepo":"octocat/Hello-World",
          "githubMeta":{"lastRefreshedAt":"2024-06-01T10:00:00Z","refreshStatus":"idle","refreshError":null}
        }
        """
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.source, "github")
        XCTAssertEqual(list.githubRepo, "octocat/Hello-World")
        XCTAssertTrue(list.isGitHubBacked)
        XCTAssertEqual(list.githubMeta?.lastRefreshedAt, "2024-06-01T10:00:00Z")
        XCTAssertEqual(list.githubMeta?.refreshStatus, "idle")
        XCTAssertNil(list.githubMeta?.refreshError)
    }

    func test_decode_gitHubList_withoutMeta_stillDecodes() throws {
        let json = #"{"id":"gh1","title":"Issues","createdAt":"2024-01-01T00:00:00Z","source":"github","githubRepo":"o/r"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertTrue(list.isGitHubBacked)
        XCTAssertNil(list.githubMeta)
    }

    func test_decode_gitHubMeta_failedStatusWithError() throws {
        let json = """
        {
          "id":"gh1","title":"Issues","createdAt":"2024-01-01T00:00:00Z",
          "source":"github","githubRepo":"o/r",
          "githubMeta":{"lastRefreshedAt":null,"refreshStatus":"failed","refreshError":"rate limited"}
        }
        """
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.githubMeta?.refreshStatus, "failed")
        XCTAssertEqual(list.githubMeta?.refreshError, "rate limited")
        XCTAssertNil(list.githubMeta?.lastRefreshedAt)
    }
}

final class UserGitHubDefaultRepoTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_withGitHubDefaultRepo() throws {
        let json = #"{"id":"u1","email":"a@b.com","username":"a","githubDefaultRepo":"octocat/Hello-World"}"#
        let user = try decoder.decode(User.self, from: Data(json.utf8))
        XCTAssertEqual(user.githubDefaultRepo, "octocat/Hello-World")
    }

    func test_decode_withoutGitHubDefaultRepo_isNil() throws {
        let json = #"{"id":"u1","email":"a@b.com","username":"a"}"#
        let user = try decoder.decode(User.self, from: Data(json.utf8))
        XCTAssertNil(user.githubDefaultRepo)
    }
}
