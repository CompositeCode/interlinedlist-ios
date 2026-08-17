import XCTest
@testable import InterlinedList

final class FollowStatusCodableTests: XCTestCase {
    // Mirrors APIClient's decoder (convertFromSnakeCase). The real
    // GET /api/follow/:id/status body is camelCase: { status, isFollowing, isPending }.
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_statusApproved_isFollowing() throws {
        let json = #"{"status":"approved","isFollowing":true,"isPending":false}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.following)
        XCTAssertFalse(s.pendingRequest)
        XCTAssertFalse(s.followedBy)
    }

    func test_decode_statusNull_notFollowing() throws {
        let json = #"{"status":null,"isFollowing":false,"isPending":false}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertFalse(s.following)
        XCTAssertFalse(s.pendingRequest)
        XCTAssertFalse(s.followedBy)
    }

    func test_decode_statusPending_isPending() throws {
        let json = #"{"status":"pending","isFollowing":false,"isPending":true}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.pendingRequest)
        XCTAssertFalse(s.following)
    }

    // The endpoint omits followedBy entirely — decode must not throw keyNotFound.
    func test_decode_missingFollowedBy_defaultsToFalse() throws {
        let json = #"{"status":"approved","isFollowing":true,"isPending":false}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertFalse(s.followedBy)
    }

    // Defensive fallback: if the boolean flags are absent, derive from `status`.
    func test_decode_flagsAbsent_derivedFromStatus() throws {
        let json = #"{"status":"pending"}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.pendingRequest)
        XCTAssertFalse(s.following)
    }

    // POST /api/follow/:id returns a nested { follow: { status, ... } } shape.
    func test_decode_nestedFollowApproved_isFollowing() throws {
        let json = #"{"follow":{"id":"f1","status":"approved","followerId":"a","followingId":"b"}}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.following)
        XCTAssertFalse(s.pendingRequest)
    }

    func test_decode_nestedFollowPending_isPending() throws {
        let json = #"{"follow":{"id":"f1","status":"pending"}}"#
        let s = try decoder.decode(FollowStatus.self, from: Data(json.utf8))
        XCTAssertTrue(s.pendingRequest)
        XCTAssertFalse(s.following)
    }

    func test_roundTrip_encodeThenDecode_preservesFlags() throws {
        let original = FollowStatus(following: true, pendingRequest: false)
        let data = try JSONEncoder().encode(original)
        let restored = try decoder.decode(FollowStatus.self, from: data)
        XCTAssertEqual(original, restored)
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
