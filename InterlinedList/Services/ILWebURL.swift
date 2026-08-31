//
//  ILWebURL.swift
//  InterlinedList
//

import Foundation

/// Builds canonical `interlinedlist.com` web permalinks for shareable content.
/// These are the public web URLs a user can paste anywhere; they are distinct from
/// the app's internal share-link tokens. Path shapes mirror the backend routes:
/// profile `/user/<username>`, message `/message/<id>`, list `/lists/<id>`,
/// document `/documents/<id>`.
enum ILWebURL {
    static let base = "https://interlinedlist.com"

    static func profile(_ username: String) -> URL? {
        make("/user", username)
    }

    static func message(_ id: String) -> URL? {
        make("/message", id)
    }

    static func list(_ id: String) -> URL? {
        make("/lists", id)
    }

    static func document(_ id: String) -> URL? {
        make("/documents", id)
    }

    /// Web landing page for a list share-link token (`/lists/shared/<token>`) — where
    /// an edit-capable link is *claimed*, since the claim endpoint is session-only.
    static func sharedList(token: String) -> URL? {
        make("/lists/shared", token)
    }

    /// Web landing page for a document share-link token (`/documents/shared/<token>`).
    static func sharedDocument(token: String) -> URL? {
        make("/documents/shared", token)
    }

    /// The canonical **public** URL for a resource, scoped to its owner's profile
    /// (`/user/<owner>/lists|documents/<id>`) — the link shown when a list/document
    /// is made public. Falls back to `nil` if owner/id are missing.
    static func publicResource(kind: ShareResourceKind, ownerUsername: String, id: String) -> URL? {
        guard !ownerUsername.isEmpty, !id.isEmpty,
              let owner = ownerUsername.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let ident = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(base)/user/\(owner)/\(kind.pathSegment)/\(ident)")
    }

    /// The authed (non-public) permalink for a resource (`/lists|documents/<id>`) —
    /// the "Get link" copy for a per-person grant; works for private resources
    /// because the grantee already has access.
    static func resource(kind: ShareResourceKind, id: String) -> URL? {
        kind == .documents ? document(id) : list(id)
    }

    private static func make(_ prefix: String, _ segment: String) -> URL? {
        guard !segment.isEmpty,
              let encoded = segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: base + prefix + "/" + encoded)
    }
}
