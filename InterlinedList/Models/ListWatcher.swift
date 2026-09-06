//
//  ListWatcher.swift
//  InterlinedList
//

import Foundation

/// A user's access role on a shared list, in ascending privilege order.
/// Wire values confirmed by the backend (GAP §B5): watcher / collaborator / manager.
enum WatcherRole: String, Codable, CaseIterable, Comparable {
    case watcher
    case collaborator
    case manager

    var label: String {
        switch self {
        case .watcher: return "Watcher"
        case .collaborator: return "Collaborator"
        case .manager: return "Manager"
        }
    }

    var detail: String { detail(for: "list") }

    /// Role description scoped to the resource being shared (e.g. "list" or
    /// "document"), so a document's share sheet doesn't say "list".
    func detail(for resourceNoun: String) -> String {
        switch self {
        case .watcher: return "Can view this \(resourceNoun)"
        case .collaborator: return "Can add and edit rows"
        case .manager: return "Can edit the schema and manage access"
        }
    }

    /// Web-aligned label for a **per-person** access grant (collaborator/watcher).
    var accessLabel: String {
        switch self {
        case .watcher: return "Read-only"
        case .collaborator: return "Edit"
        case .manager: return "Admin"
        }
    }

    /// Web-aligned label for a **share-link** role (anonymous / claimable link).
    var linkLabel: String {
        switch self {
        case .watcher: return "Viewer"
        case .collaborator: return "Editor"
        case .manager: return "Admin"
        }
    }

    /// Per-person access role description, matching the web copy.
    func accessDetail(for resourceNoun: String) -> String {
        switch self {
        case .watcher: return "Can view this \(resourceNoun)."
        case .collaborator: return "Can edit the \(resourceNoun) content."
        case .manager: return "Everything Edit can, plus settings and delete."
        }
    }

    /// Share-link role description, matching the web copy.
    var linkDetail: String {
        switch self {
        case .watcher: return "Anyone with the link can view (no account needed)."
        case .collaborator: return "A signed-in visitor can claim edit access."
        case .manager: return "A signed-in visitor can claim full admin access."
        }
    }

    /// Collaborators and managers may edit row data.
    var canEditRows: Bool { self >= .collaborator }
    /// Only managers may edit the schema and manage watchers.
    var canManage: Bool { self == .manager }

    private var rank: Int {
        switch self {
        case .watcher: return 0
        case .collaborator: return 1
        case .manager: return 2
        }
    }

    static func < (lhs: WatcherRole, rhs: WatcherRole) -> Bool { lhs.rank < rhs.rank }
}

struct ListWatcher: Identifiable, Codable {
    let id: String
    let userId: String
    let role: String
    let createdAt: String?
    let user: WatcherUser?

    var watcherRole: WatcherRole? { WatcherRole(rawValue: role) }
}

struct WatcherUser: Codable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

/// A candidate returned by the user-search endpoint when adding a watcher.
struct WatcherCandidate: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String?
    let email: String?
    let avatar: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

// MARK: - API response wrappers

struct WatchersResponse: Decodable {
    let watchers: [ListWatcher]
}

struct WatcherCandidatesResponse: Decodable {
    let users: [WatcherCandidate]
    let total: Int?
    // Note: this endpoint's `pagination` block is { limit, offset, hasMore }
    // (no `total` — that lives at the top level), so it isn't decoded into the
    // shared Pagination type. The UI only consumes `users`.
}

struct WatchingResponse: Decodable {
    let watching: Bool
    let role: String?
}
