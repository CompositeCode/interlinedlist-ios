import XCTest
@testable import InterlinedList

final class APIClientFollowTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    private let statusJSON = #"{"following":true,"followed_by":false,"pending_request":false}"#
    private let countsJSON = #"{"followers":10,"following":5}"#

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // MARK: followUser()

    func test_followUser_sendsPostToCorrectPath() async throws {
        session.stub(json: statusJSON)
        let status = try await sut.followUser(userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1") == true)
        XCTAssertTrue(status.following)
    }

    func test_followUser_401_throws() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.followUser(userId: "u1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: unfollowUser()

    func test_unfollowUser_sendsDeleteToCorrectPath() async throws {
        session.stub(data: Data(), statusCode: 204)
        try await sut.unfollowUser(userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1") == true)
    }

    // MARK: followStatus()

    func test_followStatus_sendsGetToCorrectPath() async throws {
        session.stub(json: statusJSON)
        let status = try await sut.followStatus(userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1/status") == true)
        XCTAssertTrue(status.following)
    }

    // MARK: followCounts()

    func test_followCounts_sendsGetToCorrectPath() async throws {
        session.stub(json: countsJSON)
        let counts = try await sut.followCounts(userId: "u1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1/counts") == true)
        XCTAssertEqual(counts.followers, 10)
        XCTAssertEqual(counts.following, 5)
    }

    // MARK: followRequests()

    func test_followRequests_sendsGetToCorrectPath() async throws {
        session.stub(json: #"{"requests":[{"id":"r1"}]}"#)
        let requests = try await sut.followRequests()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/follow/requests")
        XCTAssertEqual(requests.count, 1)
    }

    // MARK: approveFollowRequest() / rejectFollowRequest()

    func test_approveFollowRequest_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.approveFollowRequest(userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1/approve") == true)
    }

    func test_rejectFollowRequest_sendsPostToCorrectPath() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.rejectFollowRequest(userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1/reject") == true)
    }
}
