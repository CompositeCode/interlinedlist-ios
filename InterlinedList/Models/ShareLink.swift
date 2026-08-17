//
//  ShareLink.swift
//  InterlinedList
//

import Foundation

/// Which resource a share-link or collaborator path targets. The raw value is
/// the API path segment (`/api/lists/...` vs `/api/documents/...`).
enum ShareResourceKind: String {
    case lists
    case documents

    var pathSegment: String { rawValue }

    var singularLabel: String {
        switch self {
        case .lists: return "list"
        case .documents: return "document"
        }
    }
}

/// A tokenized share-link for a list or document. Only the resource owner can
/// create, list, or revoke these. `role` maps to `WatcherRole`.
struct ShareLink: Identifiable, Codable {
    let token: String
    let url: String
    let role: String
    let expiresAt: String?
    let createdAt: String?
    let revokedAt: String?

    var id: String { token }

    var shareRole: WatcherRole? { WatcherRole(rawValue: role) }
}

struct ShareLinksResponse: Decodable {
    let shareLinks: [ShareLink]
}

/// A per-person collaborator on a document. Mirrors `ListWatcher` for the
/// list side, but the collaborator identity fields are flattened here.
struct DocumentCollaborator: Identifiable, Codable {
    let userId: String
    let role: String
    let username: String?
    let displayName: String?
    let avatar: String?

    var id: String { userId }

    var collaboratorRole: WatcherRole? { WatcherRole(rawValue: role) }

    var displayNameOrUsername: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return username ?? "User"
    }
}

struct DocumentCollaboratorsResponse: Decodable {
    let collaborators: [DocumentCollaborator]
    let pagination: Pagination?
}
