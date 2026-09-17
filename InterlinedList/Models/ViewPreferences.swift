//
//  ViewPreferences.swift
//  InterlinedList
//

import Foundation

/// Server-side feed scope. `PATCH /api/user/update` rejects anything outside these
/// four literals with a 400, and the messages/search routes build their visibility
/// clause from the stored value — so this changes what the feed *returns*, not just
/// how it is drawn.
enum FeedScope: String, CaseIterable, Identifiable {
    case allMessages = "all_messages"
    case followingOnly = "following_only"
    case followersOnly = "followers_only"
    case myMessages = "my_messages"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allMessages: return "Everyone"
        case .followingOnly: return "People I follow"
        case .followersOnly: return "My followers"
        case .myMessages: return "Only me"
        }
    }

    /// Unknown or missing values fall back to the server's own default rather than
    /// failing, so a value added server-side never breaks the picker.
    static func from(_ raw: String?) -> FeedScope {
        guard let raw, let scope = FeedScope(rawValue: raw) else { return .allMessages }
        return scope
    }
}

/// The ranges `app/api/user/update/route.ts` validates. Mirrored here so the
/// steppers cannot produce a value the route would 400 on.
enum ViewPreferenceBounds {
    static let messagesPerPage = 10...30
    static let notificationTrayLimit = 10...40

    /// Feed page size when the account has never set one. The feed shipped with a
    /// hardcoded 50, which is above the settable maximum — preserved as the
    /// unset-default so existing installs do not silently start paging smaller.
    static let defaultMessagesPerPage = 50
    static let defaultNotificationTrayLimit = 20

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
