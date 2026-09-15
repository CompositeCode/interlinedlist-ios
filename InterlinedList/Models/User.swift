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
    /// Private account: new followers need approval and posts stay visible only
    /// to approved followers. Drives the follow-request flow server-side.
    let isPrivateAccount: Bool?
    /// Server-side feed scope. One of `all_messages`, `following_only`,
    /// `followers_only`, `my_messages` — the messages and search routes build
    /// their visibility clause from this, so it changes what the feed returns.
    let viewingPreference: String?
    /// Feed page size (server accepts 10–30).
    let messagesPerPage: Int?
    /// Render link previews in the feed.
    let showPreviews: Bool?
    /// How many notifications `?scope=tray` returns (server accepts 10–40).
    let notificationTrayLimit: Int?

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
         githubDefaultRepo: String? = nil, isPrivateAccount: Bool? = nil,
         viewingPreference: String? = nil, messagesPerPage: Int? = nil,
         showPreviews: Bool? = nil, notificationTrayLimit: Int? = nil) {
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
        self.isPrivateAccount = isPrivateAccount
        self.viewingPreference = viewingPreference
        self.messagesPerPage = messagesPerPage
        self.showPreviews = showPreviews
        self.notificationTrayLimit = notificationTrayLimit
    }
}

struct UserResponse: Codable {
    let user: User
}
