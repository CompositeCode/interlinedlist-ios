//
//  SharedResolution.swift
//  InterlinedList
//

import Foundation

/// Result of resolving a document share-link token via
/// `GET /api/documents/shared/:token` (G10). The read view is available to anyone
/// with the link; `role` is `watcher`/`collaborator`/`manager`. Edit-capable links
/// (`collaborator`/`manager`) require a session-cookie **claim** (`needsAuth`) that
/// the Bearer-only iOS client can't perform — so on iOS these resolve to a
/// read-only reader with a note to claim on the web.
struct SharedDocumentResolution: Codable {
    let role: String?
    let canClaim: Bool?
    let needsAuth: Bool?
    let document: Document

    /// Whether the link grants edit rights (vs. a plain viewer link).
    var isEditLink: Bool { role == "collaborator" || role == "manager" }
}

/// The list metadata returned by `GET /api/lists/shared/:token`. The token grants
/// no schema access (that endpoint needs watcher+ auth), so rows are fetched
/// separately via `GET /api/lists/shared/:token/data` and rendered schema-less.
struct SharedListInfo: Codable {
    let id: String
    let title: String
    let description: String?
    let isPublic: Bool?
    let updatedAt: String?
}

/// Result of resolving a list share-link token via `GET /api/lists/shared/:token`.
/// Mirrors `SharedDocumentResolution`: the read view is available to anyone with the
/// link; edit-capable links (`collaborator`/`manager`) need a session-cookie **claim**
/// the Bearer-only iOS client can't perform, so they resolve to a read-only viewer
/// with a button to accept on the web.
struct SharedListResolution: Codable {
    let role: String?
    let canClaim: Bool?
    let needsAuth: Bool?
    let list: SharedListInfo

    var isEditLink: Bool { role == "collaborator" || role == "manager" }
}
