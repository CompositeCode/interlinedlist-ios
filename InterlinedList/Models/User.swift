//
//  User.swift
//  InterlinedList
//

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let username: String
    let displayName: String?
    let avatar: String?
    let bio: String?
    let theme: String?
    let emailVerified: Bool?
    let createdAt: String?
    /// Max characters allowed per message (from user settings). API default is 666.
    let maxMessageLength: Int?
    /// Whether to show the advanced post settings bar by default.
    let showAdvancedPostSettings: Bool?
    /// Default visibility for new messages (true = public).
    let defaultPubliclyVisible: Bool?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

struct UserResponse: Codable {
    let user: User
}
