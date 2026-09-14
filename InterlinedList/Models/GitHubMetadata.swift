//
//  GitHubMetadata.swift
//  InterlinedList
//

import Foundation

/// Repo metadata used to fill in GitHub-backed list rows: the repo's real labels
/// and assignable users, the orgs the linked account belongs to, and the next
/// issue number.
///
/// `/api/github/repos/:owner/:repo/{labels,assignees}` forward the **raw GitHub
/// REST arrays**, so these decode through `APIClient`'s `convertFromSnakeCase`
/// decoder (`avatar_url` → `avatarUrl`). Decode defensively: only the identifying
/// field is required.

struct GitHubLabel: Decodable, Identifiable, Hashable {
    let name: String
    let color: String?
    let description: String?

    var id: String { name }
}

struct GitHubAssignee: Decodable, Identifiable, Hashable {
    let login: String
    let avatarUrl: String?

    var id: String { login }
}

struct GitHubOrg: Decodable, Identifiable, Hashable {
    let login: String
    let avatarUrl: String?

    var id: String { login }
}

/// `GET /api/github/orgs` has been observed returning **both** a bare array and
/// an `{ orgs: [...] }` envelope depending on deployment, so accept either.
struct GitHubOrgsResponse: Decodable {
    let orgs: [GitHubOrg]

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let list = try? container.decode([GitHubOrg].self) {
            orgs = list
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        orgs = try keyed.decodeIfPresent([GitHubOrg].self, forKey: .orgs) ?? []
    }

    private enum CodingKeys: String, CodingKey { case orgs }
}

struct GitHubNextIssueNumber: Decodable {
    let nextNumber: Int
}
