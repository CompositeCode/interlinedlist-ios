//
//  MuteStore.swift
//  InterlinedList
//

import Foundation

/// The two `/api/users/{id}/mute` calls plus the seed list. Kept narrow (ISP) so
/// `MuteStore` can be tested against a mock without the full `APIClient`.
protocol MuteAPI {
    func mutedUsers(limit: Int, offset: Int) async throws -> MutedUsersResponse
    func muteUser(id: String) async throws
    func unmuteUser(id: String) async throws
}

extension APIClient: MuteAPI {}

/// Who this user has muted, shared by every screen that can mute or has to hide
/// muted authors.
///
/// A singleton rather than an `@EnvironmentObject` because the mute entry points
/// sit behind sheets (`MessageDetailView`, `MessageThreadView`, `UserProfileView`)
/// that would each have to re-inject it; observing `MuteStore.shared` means a mute
/// from any of them republishes into the feed with no manual refresh.
@MainActor
final class MuteStore: ObservableObject {
    static let shared = MuteStore()

    @Published private(set) var mutedUsers: [MutedUser] = []
    @Published private(set) var mutedUserIds: Set<String> = []

    private var hasLoaded = false
    private let api: MuteAPI

    init(api: MuteAPI = APIClient.shared) {
        self.api = api
    }

    func isMuted(_ userId: String) -> Bool {
        mutedUserIds.contains(userId)
    }

    /// Seeds from `GET /api/user/mutes`. Callers that just need the filter to be
    /// right (the feed, a profile) use this; it fetches once per launch.
    func loadIfNeeded() async throws {
        guard !hasLoaded else { return }
        try await refresh()
    }

    func refresh() async throws {
        let response = try await api.mutedUsers(limit: 100, offset: 0)
        mutedUsers = response.mutedUsers
        mutedUserIds = Set(response.mutedUsers.map(\.id))
        hasLoaded = true
    }

    /// Optimistic: the author drops out of the feed on tap and comes back if the
    /// call fails, so a mute never looks applied when the server rejected it. The
    /// error is rethrown for the view to route (a 401 goes to `handleUnauthorized`).
    func mute(userId: String, username: String, displayName: String? = nil) async throws {
        guard !userId.isEmpty, !mutedUserIds.contains(userId) else { return }
        let optimistic = MutedUser(id: userId, username: username, displayName: displayName, avatar: nil)
        mutedUsers.append(optimistic)
        mutedUserIds.insert(userId)
        do {
            try await api.muteUser(id: userId)
        } catch {
            mutedUsers.removeAll { $0.id == userId }
            mutedUserIds.remove(userId)
            throw error
        }
    }

    func unmute(userId: String) async throws {
        guard !userId.isEmpty else { return }
        let previous = mutedUsers.first { $0.id == userId }
        let wasMuted = mutedUserIds.contains(userId)
        mutedUsers.removeAll { $0.id == userId }
        mutedUserIds.remove(userId)
        do {
            try await api.unmuteUser(id: userId)
        } catch {
            if let previous { mutedUsers.append(previous) }
            if wasMuted { mutedUserIds.insert(userId) }
            throw error
        }
    }
}

/// The author a mute confirmation is about. Shared by the three post menus so the
/// dialog copy and the store call agree on who is being muted.
struct MuteTarget: Identifiable {
    let id: String
    let username: String
    var displayName: String? = nil
}

extension MuteTarget {
    init(message: Message) {
        self.init(
            id: message.userId,
            username: message.user?.username ?? "",
            displayName: message.user?.displayName
        )
    }
}

enum MuteCopy {
    static func confirmTitle(_ username: String) -> String { "Mute @\(username)?" }
    static func unmuteTitle(_ username: String) -> String { "Unmute @\(username)?" }
    /// Says what mute does *and* what it does not, because the neighbouring menu
    /// item is Block and the two are easy to confuse.
    static let confirmMessage = "You won't see their posts in your feed. Unlike blocking, they can still follow you, message you, and see your posts."
    static let unmuteMessage = "Their posts will show up in your feed again."
}
