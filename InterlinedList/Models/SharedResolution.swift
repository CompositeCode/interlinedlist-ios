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
