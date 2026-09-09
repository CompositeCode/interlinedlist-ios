//
//  APIClient+ListContributors.swift
//  InterlinedList
//

import Foundation

/// Who has actually contributed rows to a list.
///
/// Read-only: this extension adds no write path. Row mutations — GitHub-backed
/// ones especially, which must send the full row through `updateItem` — are
/// untouched by anything here.
extension APIClient {

    /// `GET /api/lists/{id}/contributors` — the full ranked contributor set,
    /// ordered by score (added + edited) descending, then added, then username.
    /// The route does not page.
    ///
    /// Returns an empty set for GitHub-backed lists by design; callers should
    /// skip the request entirely for those rather than rely on the empty answer.
    func listContributors(listId: String) async throws -> ListContributorsResult {
        let encoded = listId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listId
        return try await get("/api/lists/\(encoded)/contributors")
    }
}
