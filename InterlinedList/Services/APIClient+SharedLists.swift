//
//  APIClient+SharedLists.swift
//  InterlinedList
//

import Foundation

/// Lists owned by **other** users that the current user can reach.
///
/// `GET /api/lists` is owner-scoped on the backend (`where: { userId: user.id }`),
/// so a list shared *to* someone never appears there. The web has a dedicated
/// "Lists you're watching" tree for exactly this; without the route below a
/// shared list is unreachable in the app except by following a share link.
extension APIClient {

    /// `GET /api/lists/watching` — every list the user holds a `ListWatcher` row
    /// on, public or private, ordered most-recently-updated first. Each list
    /// carries the viewer's own `role` on it.
    func listsWatching(limit: Int = 50, offset: Int = 0) async throws -> [UserList] {
        struct Response: Decodable { let lists: [UserList] }
        let response: Response = try await get("/api/lists/watching?limit=\(limit)&offset=\(offset)")
        return response.lists
    }
}
