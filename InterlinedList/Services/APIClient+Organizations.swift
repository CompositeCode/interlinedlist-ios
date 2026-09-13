//
//  APIClient+Organizations.swift
//  InterlinedList
//

import Foundation

/// `.urlQueryAllowed` deliberately permits the sub-delimiters `&`, `=`, `+` and
/// `?` — they are legal *somewhere* in a query string. Encoding a value with it
/// therefore lets a user-typed `&` split the query into an extra parameter, so a
/// search for `"ada l&ve"` reaches the backend as `search=ada l`. Strip the
/// delimiters so a value stays one value. `+` is included because the backend
/// reads params via `URLSearchParams`, which decodes `+` as a space.
private let orgQueryValueAllowed: CharacterSet = {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+?#")
    return allowed
}()

/// Organization discovery and member recruitment.
///
/// These are the two reads that `APIClient`'s existing `addOrganizationMember`
/// and `joinOrganization` writes had no counterpart for: without a candidate
/// search there is nobody to add, and without a public directory there is
/// nothing to join.
extension APIClient {

    /// `GET /api/organizations/{id}/users` — users who are **not** yet members,
    /// for the add-member picker.
    ///
    /// **Owner-gated.** The route rejects admins as well as members with
    /// `403 "Only organization owners can search for users to add"`. That body
    /// carries an `error` field, so it surfaces as `APIError.forbidden` rather
    /// than `.status(403)` — callers must catch both and hide the affordance.
    ///
    /// Omitting `excludeMembers` makes the backend exclude every current member
    /// itself, so pass it only to exclude a narrower set.
    func organizationUsers(id: String,
                           search: String? = nil,
                           excludeMembers: [String]? = nil,
                           limit: Int = 20,
                           offset: Int = 0) async throws -> [OrganizationUser] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var path = "/api/organizations/\(encoded)/users?limit=\(limit)&offset=\(offset)"
        if let search, !search.isEmpty {
            let query = search.addingPercentEncoding(withAllowedCharacters: orgQueryValueAllowed) ?? search
            path += "&search=\(query)"
        }
        if let excludeMembers, !excludeMembers.isEmpty {
            let joined = excludeMembers.joined(separator: ",")
            let query = joined.addingPercentEncoding(withAllowedCharacters: orgQueryValueAllowed) ?? joined
            path += "&excludeMembers=\(query)"
        }
        let response: OrganizationUsersResponse = try await get(path)
        return response.users
    }

    /// `GET /api/organizations?public=true` — the joinable public directory.
    ///
    /// The bare `/api/organizations` call folds in the viewer's own *private*
    /// orgs, which already have their own list. `public=true` returns public orgs
    /// only, and merges the viewer's `userRole` into each row so one they already
    /// belong to renders as a membership instead of offering a Join that the
    /// backend would reject as a duplicate.
    func publicOrganizations(limit: Int = 20, offset: Int = 0) async throws -> (orgs: [Organization], pagination: Pagination?) {
        let response: OrganizationsResponse = try await get("/api/organizations?public=true&limit=\(limit)&offset=\(offset)")
        return (response.organizations, response.pagination)
    }
}
