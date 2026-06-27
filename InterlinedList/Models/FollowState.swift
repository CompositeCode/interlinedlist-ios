//
//  FollowState.swift
//  InterlinedList
//

import Foundation

struct FollowStatus: Codable {
    let following: Bool
    let followedBy: Bool
    let pendingRequest: Bool
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
