//
//  APIClient+Materialize.swift
//  InterlinedList
//

import Foundation

extension APIClient {
    /// Creates a List, a Document, or both from an existing object
    /// (`POST /api/materialize`, Bearer, camelCase body).
    ///
    /// **Subscriber-only** — a free account gets `403` ("Subscribe to create
    /// lists and documents."), so callers must hide the affordance rather than
    /// surface a paywall. `404` means a referenced id isn't owned by the caller;
    /// `400` means a bad config (no title, no columns, unsupported source).
    ///
    /// `listConfig` is **required** whenever `target` creates a list — the server
    /// rejects a missing title or an empty column set. `docConfig` is optional;
    /// the server derives defaults for anything omitted.
    func materialize(target: MaterializeTarget,
                     source: MaterializeSourceRef,
                     listConfig: MaterializeListConfig? = nil,
                     docConfig: MaterializeDocConfig? = nil) async throws -> MaterializeResult {
        let body = MaterializeRequest(
            target: target,
            source: source,
            listConfig: target.createsList ? listConfig : nil,
            docConfig: target.createsDocument ? docConfig : nil
        )
        return try await postCamel("/api/materialize", body: body)
    }
}
