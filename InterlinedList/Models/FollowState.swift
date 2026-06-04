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
