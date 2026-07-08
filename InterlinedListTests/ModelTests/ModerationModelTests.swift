import XCTest
@testable import InterlinedList

final class ModerationModelTests: XCTestCase {
    private let decoder = JSONDecoder()

    // MARK: - BlockedUser

    func test_blockedUser_decodes_fullObject() throws {
        let json = #"{"id":"u1","username":"alice","displayName":"Alice Smith","avatar":"https://example.com/a.jpg"}"#
        let user = try decoder.decode(BlockedUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.id, "u1")
        XCTAssertEqual(user.username, "alice")
        XCTAssertEqual(user.displayName, "Alice Smith")
        XCTAssertEqual(user.avatar, "https://example.com/a.jpg")
    }

    func test_blockedUser_decodes_nullOptionalFields() throws {
        let json = #"{"id":"u2","username":"bob","displayName":null,"avatar":null}"#
        let user = try decoder.decode(BlockedUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.id, "u2")
        XCTAssertEqual(user.username, "bob")
        XCTAssertNil(user.displayName)
        XCTAssertNil(user.avatar)
    }

    // MARK: - BlockedUsersResponse

    func test_blockedUsersResponse_decodes_emptyList() throws {
        let json = #"{"blockedUsers":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#
        let resp = try decoder.decode(BlockedUsersResponse.self, from: Data(json.utf8))
        XCTAssertTrue(resp.blockedUsers.isEmpty)
        XCTAssertEqual(resp.pagination?.total, 0)
        XCTAssertEqual(resp.pagination?.hasMore, false)
    }

    func test_blockedUsersResponse_decodes_multipleUsers() throws {
        let json = #"""
        {
          "blockedUsers": [
            {"id":"u1","username":"alice","displayName":"Alice","avatar":null},
            {"id":"u2","username":"bob","displayName":null,"avatar":null}
          ],
          "pagination": {"total":2,"limit":20,"offset":0,"hasMore":false}
        }
        """#
        let resp = try decoder.decode(BlockedUsersResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.blockedUsers.count, 2)
        XCTAssertEqual(resp.blockedUsers[0].id, "u1")
        XCTAssertEqual(resp.blockedUsers[1].username, "bob")
    }

    func test_blockedUsersResponse_decodes_nullPagination() throws {
        let json = #"{"blockedUsers":[],"pagination":null}"#
        let resp = try decoder.decode(BlockedUsersResponse.self, from: Data(json.utf8))
        XCTAssertNil(resp.pagination)
    }

    // MARK: - MutedUser

    func test_mutedUser_decodes_fullObject() throws {
        let json = #"{"id":"u3","username":"carol","displayName":"Carol","avatar":"https://example.com/c.jpg"}"#
        let user = try decoder.decode(MutedUser.self, from: Data(json.utf8))
        XCTAssertEqual(user.id, "u3")
        XCTAssertEqual(user.username, "carol")
        XCTAssertEqual(user.displayName, "Carol")
        XCTAssertEqual(user.avatar, "https://example.com/c.jpg")
    }

    func test_mutedUser_decodes_nullOptionalFields() throws {
        let json = #"{"id":"u4","username":"dave","displayName":null,"avatar":null}"#
        let user = try decoder.decode(MutedUser.self, from: Data(json.utf8))
        XCTAssertNil(user.displayName)
        XCTAssertNil(user.avatar)
    }

    // MARK: - MutedUsersResponse

    func test_mutedUsersResponse_decodes_emptyList() throws {
        let json = #"{"mutedUsers":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#
        let resp = try decoder.decode(MutedUsersResponse.self, from: Data(json.utf8))
        XCTAssertTrue(resp.mutedUsers.isEmpty)
        XCTAssertEqual(resp.pagination?.total, 0)
    }

    func test_mutedUsersResponse_decodes_multipleUsers() throws {
        let json = #"""
        {
          "mutedUsers": [
            {"id":"u5","username":"eve","displayName":"Eve","avatar":null}
          ],
          "pagination": {"total":1,"limit":20,"offset":0,"hasMore":false}
        }
        """#
        let resp = try decoder.decode(MutedUsersResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.mutedUsers.count, 1)
        XCTAssertEqual(resp.mutedUsers[0].displayName, "Eve")
    }
}
