//
//  FollowState.swift
//  InterlinedList
//

import Foundation

/// The caller's relationship toward a target user.
///
/// Decoded from two different API shapes:
/// - `GET /api/follow/:id/status` → `{ status, isFollowing, isPending }` (no `followedBy`).
/// - `POST /api/follow/:id`       → `{ follow: { status, ... } }` (nested; derive from `status`).
///
/// `followedBy` (does the target follow us back) is not reported by either endpoint,
/// so it defaults to `false`; nothing in the UI depends on a real value from these calls.
struct FollowStatus: Codable, Equatable {
    let following: Bool
    let followedBy: Bool
    let pendingRequest: Bool

    init(following: Bool, followedBy: Bool = false, pendingRequest: Bool) {
        self.following = following
        self.followedBy = followedBy
        self.pendingRequest = pendingRequest
    }

    private enum CodingKeys: String, CodingKey {
        case status, isFollowing, isPending, follow
    }

    private struct NestedFollow: Decodable {
        let status: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let nested = try container.decodeIfPresent(NestedFollow.self, forKey: .follow) {
            let status = nested.status
            self.following = status == "approved"
            self.pendingRequest = status == "pending"
        } else {
            let status = try container.decodeIfPresent(String.self, forKey: .status)
            self.following = try container.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? (status == "approved")
            self.pendingRequest = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? (status == "pending")
        }
        self.followedBy = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(following, forKey: .isFollowing)
        try container.encode(pendingRequest, forKey: .isPending)
        try container.encode(following ? "approved" : (pendingRequest ? "pending" : nil), forKey: .status)
    }
}

struct FollowCounts: Codable {
    let followers: Int
    let following: Int
}

struct FollowRequest: Identifiable, Codable {
    let id: String
    let user: MessageUser?
    let createdAt: String?
}

struct FollowRequestsResponse: Codable {
    let requests: [FollowRequest]
}

/// A user appearing in a followers / following list.
struct FollowUser: Identifiable, Codable, Equatable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
    let followId: String?
    /// "accepted" | "pending" (relationship status of this edge).
    let status: String?
    let createdAt: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

struct FollowersResponse: Codable {
    let followers: [FollowUser]
    let pagination: Pagination?
}

struct FollowingResponse: Codable {
    let following: [FollowUser]
    let pagination: Pagination?
}

/// Mutual-connection counts between the current user and another user.
/// Note: the endpoint returns counts only, not a user list.
struct MutualCounts: Codable, Equatable {
    let mutualFollowers: Int
    let mutualFollowing: Int
}
