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
    /// The user's default GitHub repo ("owner/repo") for GitHub-backed lists,
    /// or nil if none is set. Serialized camelCase by the API.
    let githubDefaultRepo: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }

    var isSubscriber: Bool {
        customerStatus?.hasPrefix("subscriber") == true
    }

    // Explicit memberwise init defaults `githubDefaultRepo` so existing call
    // sites (previews, tests) compile without supplying it.
    init(id: String, email: String, username: String, displayName: String?,
         avatar: String?, bio: String?, theme: String?, emailVerified: Bool?,
         createdAt: String?, maxMessageLength: Int?, showAdvancedPostSettings: Bool?,
         defaultPubliclyVisible: Bool?, customerStatus: String?,
         githubDefaultRepo: String? = nil) {
        self.id = id
        self.email = email
        self.username = username
        self.displayName = displayName
        self.avatar = avatar
        self.bio = bio
        self.theme = theme
        self.emailVerified = emailVerified
        self.createdAt = createdAt
        self.maxMessageLength = maxMessageLength
        self.showAdvancedPostSettings = showAdvancedPostSettings
        self.defaultPubliclyVisible = defaultPubliclyVisible
        self.customerStatus = customerStatus
        self.githubDefaultRepo = githubDefaultRepo
    }
}

struct UserResponse: Codable {
    let user: User
}
