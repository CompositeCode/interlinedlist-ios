import XCTest
@testable import InterlinedList

/// W2 (#47). The store is what makes a mute visible: the feed filters on it, and
/// every menu reads its state, so an optimistic insert that is never rolled back
/// would hide an author the server never muted.
@MainActor
final class MuteStoreTests: XCTestCase {

    private struct Boom: Error {}

    private final class MockMuteAPI: MuteAPI {
        var seeded: [MutedUser] = []
        var muteError: Error?
        var unmuteError: Error?
        var listError: Error?
        private(set) var mutedIds: [String] = []
        private(set) var unmutedIds: [String] = []
        private(set) var listCallCount = 0

        func mutedUsers(limit: Int, offset: Int) async throws -> MutedUsersResponse {
            listCallCount += 1
            if let listError { throw listError }
            return MutedUsersResponse(mutedUsers: seeded, pagination: nil)
        }

        func muteUser(id: String) async throws {
            mutedIds.append(id)
            if let muteError { throw muteError }
        }

        func unmuteUser(id: String) async throws {
            unmutedIds.append(id)
            if let unmuteError { throw unmuteError }
        }
    }

    private func makeUser(_ id: String, _ username: String) -> MutedUser {
        MutedUser(id: id, username: username, displayName: nil, avatar: nil)
    }

    // MARK: seeding

    func test_refresh_seedsIdsFromTheMutesEndpoint() async throws {
        let api = MockMuteAPI()
        api.seeded = [makeUser("u1", "alice"), makeUser("u2", "bob")]
        let sut = MuteStore(api: api)

        try await sut.refresh()

        XCTAssertEqual(sut.mutedUserIds, ["u1", "u2"])
        XCTAssertTrue(sut.isMuted("u1"))
        XCTAssertFalse(sut.isMuted("u3"))
    }

    func test_loadIfNeeded_fetchesOnlyOnce() async throws {
        let api = MockMuteAPI()
        let sut = MuteStore(api: api)

        try await sut.loadIfNeeded()
        try await sut.loadIfNeeded()

        XCTAssertEqual(api.listCallCount, 1)
    }

    /// A failed seed must not latch — the next screen should get to try again,
    /// otherwise one flaky launch request leaves the feed unfiltered all session.
    func test_loadIfNeeded_afterAFailure_retries() async {
        let api = MockMuteAPI()
        api.listError = Boom()
        let sut = MuteStore(api: api)

        try? await sut.loadIfNeeded()
        api.listError = nil
        try? await sut.loadIfNeeded()

        XCTAssertEqual(api.listCallCount, 2)
    }

    // MARK: mute

    func test_mute_callsTheEndpointAndRecordsTheId() async throws {
        let api = MockMuteAPI()
        let sut = MuteStore(api: api)

        try await sut.mute(userId: "u1", username: "alice")

        XCTAssertEqual(api.mutedIds, ["u1"])
        XCTAssertTrue(sut.isMuted("u1"))
        XCTAssertEqual(sut.mutedUsers.first?.username, "alice")
    }

    func test_mute_failure_rollsBackTheOptimisticInsert() async {
        let api = MockMuteAPI()
        api.muteError = Boom()
        let sut = MuteStore(api: api)

        do {
            try await sut.mute(userId: "u1", username: "alice")
            XCTFail("Expected throw")
        } catch {
            XCTAssertFalse(sut.isMuted("u1"))
            XCTAssertTrue(sut.mutedUsers.isEmpty)
        }
    }

    /// A 401 from a feature endpoint has to reach the view so it can route through
    /// `handleUnauthorized` rather than being swallowed as a generic failure.
    func test_mute_401_rethrowsTheAPIError() async {
        let api = MockMuteAPI()
        api.muteError = APIError.status(401)
        let sut = MuteStore(api: api)

        do {
            try await sut.mute(userId: "u1", username: "alice")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Expected APIError.status, got \(error)")
        }
    }

    func test_mute_alreadyMutedUser_isANoOp() async throws {
        let api = MockMuteAPI()
        api.seeded = [makeUser("u1", "alice")]
        let sut = MuteStore(api: api)
        try await sut.refresh()

        try await sut.mute(userId: "u1", username: "alice")

        XCTAssertTrue(api.mutedIds.isEmpty)
        XCTAssertEqual(sut.mutedUsers.count, 1)
    }

    func test_mute_emptyUserId_isANoOp() async throws {
        let api = MockMuteAPI()
        let sut = MuteStore(api: api)

        try await sut.mute(userId: "", username: "alice")

        XCTAssertTrue(api.mutedIds.isEmpty)
    }

    // MARK: unmute

    func test_unmute_callsTheEndpointAndClearsTheId() async throws {
        let api = MockMuteAPI()
        api.seeded = [makeUser("u1", "alice")]
        let sut = MuteStore(api: api)
        try await sut.refresh()

        try await sut.unmute(userId: "u1")

        XCTAssertEqual(api.unmutedIds, ["u1"])
        XCTAssertFalse(sut.isMuted("u1"))
        XCTAssertTrue(sut.mutedUsers.isEmpty)
    }

    func test_unmute_failure_restoresTheEntry() async throws {
        let api = MockMuteAPI()
        api.seeded = [makeUser("u1", "alice")]
        let sut = MuteStore(api: api)
        try await sut.refresh()
        api.unmuteError = Boom()

        do {
            try await sut.unmute(userId: "u1")
            XCTFail("Expected throw")
        } catch {
            XCTAssertTrue(sut.isMuted("u1"))
            XCTAssertEqual(sut.mutedUsers.first?.username, "alice")
        }
    }

    func test_unmute_401_rethrowsTheAPIError() async throws {
        let api = MockMuteAPI()
        api.seeded = [makeUser("u1", "alice")]
        let sut = MuteStore(api: api)
        try await sut.refresh()
        api.unmuteError = APIError.status(401)

        do {
            try await sut.unmute(userId: "u1")
            XCTFail("Expected throw")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Expected APIError.status, got \(error)")
        }
    }

    // MARK: copy

    /// The whole point of the confirmation is telling mute apart from block.
    func test_confirmMessage_saysWhatMuteDoesNotDo() {
        XCTAssertTrue(MuteCopy.confirmMessage.contains("blocking"))
        XCTAssertTrue(MuteCopy.confirmMessage.contains("message you"))
        XCTAssertEqual(MuteCopy.confirmTitle("alice"), "Mute @alice?")
        XCTAssertEqual(MuteCopy.unmuteTitle("alice"), "Unmute @alice?")
    }
}
