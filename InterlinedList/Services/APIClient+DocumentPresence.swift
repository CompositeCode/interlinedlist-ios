//
//  APIClient+DocumentPresence.swift
//  InterlinedList
//

import Foundation

extension APIClient {
    /// Combined heartbeat and poll: records this account as active in the document
    /// and returns the *other* active editors plus the document's current version.
    ///
    /// Both caret offsets are optional — sending neither still registers presence,
    /// which is what iOS does (it reports "viewing", not a caret position).
    func documentPresence(id: String, anchor: Int? = nil, head: Int? = nil) async throws -> DocumentPresenceResponse {
        struct Body: Encodable {
            let anchor: Int?
            let head: Int?
        }
        return try await postCamel(
            "/api/documents/\(pathSegment(id))/presence",
            body: Body(anchor: anchor, head: head)
        )
    }

    /// Explicit leave, so peers drop this viewer immediately instead of waiting for
    /// the server's 8-second active window to lapse.
    func leaveDocumentPresence(id: String) async throws {
        try await delete("/api/documents/\(pathSegment(id))/presence")
    }
}
