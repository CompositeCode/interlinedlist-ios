import XCTest
@testable import InterlinedList

final class FollowStatusCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_allFields() throws {
        let json = #"{"following":true,"followed_by":false,"pending_request":false}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.following)
        XCTAssertFalse(s.followedBy)
        XCTAssertFalse(s.pendingRequest)
    }

    func test_decode_pendingRequest() throws {
        let json = #"{"following":false,"followed_by":false,"pending_request":true}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.pendingRequest)
        XCTAssertFalse(s.following)
    }
}

final class FollowCountsCodableTests: XCTestCase {
    func test_decode_followCounts() throws {
        let json = #"{"followers":42,"following":7}"#
        let c = try JSONDecoder().decode(FollowCounts.self, from: Data(json.utf8))
        XCTAssertEqual(c.followers, 42)
        XCTAssertEqual(c.following, 7)
    }
}

final class FollowRequestCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_withUser() throws {
        let json = #"""
        {"id":"r1","user":{"id":"u1","username":"bob","display_name":"Bob","avatar":null},
         "created_at":"2024-01-01T00:00:00Z"}
        """#
        let r = try decoder.decode(FollowRequest.self, from: Data(json.utf8))
        XCTAssertEqual(r.id, "r1")
        XCTAssertEqual(r.user?.username, "bob")
    }

    func test_decode_nullUser() throws {
        let json = #"{"id":"r2","user":null}"#
        let r = try decoder.decode(FollowRequest.self, from: Data(json.utf8))
        XCTAssertNil(r.user)
    }

    func test_decode_followRequestsResponse() throws {
        let json = #"{"requests":[{"id":"r1"},{"id":"r2"}]}"#
        let r = try decoder.decode(FollowRequestsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.requests.count, 2)
    }
}
