//
//  DocumentPresence.swift
//  InterlinedList
//

import Foundation

/// Another editor currently active in a document. `anchor`/`head` are caret
/// offsets; iOS does not mirror remote carets (out of scope for v1) but decodes
/// them so the shape matches the route and a later version needs no migration.
struct DocumentPresenceUser: Codable, Identifiable, Hashable {
    let userId: String
    let name: String
    let color: String?
    let anchor: Int?
    let head: Int?

    var id: String { userId }
}

/// Response to the combined heartbeat + poll. `users` excludes the caller.
struct DocumentPresenceResponse: Codable {
    let users: [DocumentPresenceUser]
    /// The document's current server-side version — a cheap staleness signal.
    let version: Int?
}
