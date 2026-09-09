//
//  APIClient+Lists.swift
//  InterlinedList
//

import Foundation

/// Why a list a permalink points at cannot be shown.
enum ListAccessError: Error {
    /// The viewer holds no role on this list (403), or it does not exist / is
    /// deleted (404). The backend deliberately answers both for a list the
    /// viewer may not see, so they collapse into one user-facing state.
    case noAccess
}

extension APIClient {
    /// A single list by id (`GET /api/lists/:id`).
    ///
    /// Bearer-ready, and authorized by *role* — owner / manager / collaborator /
    /// watcher — so a bare `/lists/<id>` permalink needs no owner username in the
    /// URL to resolve. Throws `ListAccessError.noAccess` for 403/404.
    func list(id: String) async throws -> UserList {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        struct Response: Decodable {
            let data: UserList
        }
        let response: Response = try await get(
            "/api/lists/\(encoded)",
            mappingStatuses: [403: ListAccessError.noAccess, 404: ListAccessError.noAccess]
        )
        return response.data
    }
}
