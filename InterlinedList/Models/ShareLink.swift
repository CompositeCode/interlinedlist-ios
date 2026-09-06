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

/// Expiry presets for share links and email invites, matching the web
/// (Never / 7 days / 30 days). The client resolves a preset to an ISO-8601
/// `expiresAt` the API accepts (`nil` for Never).
enum ShareExpiryPreset: String, CaseIterable, Identifiable {
    case never
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: return "Never"
        case .week: return "7 days"
        case .month: return "30 days"
        }
    }

    private var days: Int? {
        switch self {
        case .never: return nil
        case .week: return 7
        case .month: return 30
        }
    }

    /// The ISO-8601 `expiresAt` this preset maps to, or `nil` for "Never".
    func expiresAt(from now: Date = Date()) -> String? {
        guard let days, let date = Calendar.current.date(byAdding: .day, value: days, to: now) else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
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
