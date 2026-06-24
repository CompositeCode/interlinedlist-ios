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
    /// Subscription state from the API. Known values: "free", "subscriber",
    /// "subscriber:monthly", "subscriber:annual". Any prefix of "subscriber"
    /// grants subscriber access. Optional because older API deployments
    /// may omit the field.
    let customerStatus: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }

    var isSubscriber: Bool {
        customerStatus?.hasPrefix("subscriber") == true
    }
}

struct UserResponse: Codable {
    let user: User
}
