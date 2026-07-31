//
//  GitHub.swift
//  InterlinedList
//

import Foundation

/// A repository returned by `GET /api/github/repos`, which forwards the raw
/// GitHub REST array. GitHub uses snake_case on the wire (`full_name`,
/// `html_url`) and a nested `owner.login`. These types are decoded through
/// `APIClient`'s `convertFromSnakeCase` decoder, which rewrites incoming keys
/// BEFORE `CodingKeys` are matched — so `full_name` arrives as `fullName`,
/// `html_url` as `htmlUrl`, while single-word keys like `private`/`owner` are
/// unchanged. The `CodingKeys` below therefore use the CONVERTED names.
/// Decode defensively: only `fullName` is required.
struct GitHubRepo: Codable, Identifiable, Hashable {
    let fullName: String
    let name: String?
    let isPrivate: Bool?
    let ownerLogin: String?

    var id: String { fullName }

    /// The `owner` portion ("octocat/Hello-World" → "octocat").
    var owner: String {
        ownerLogin ?? String(fullName.prefix(while: { $0 != "/" }))
    }

    /// The repo portion ("octocat/Hello-World" → "Hello-World").
    var repo: String {
        if let name, !name.isEmpty { return name }
        guard let slash = fullName.firstIndex(of: "/") else { return fullName }
        return String(fullName[fullName.index(after: slash)...])
    }

    // convertFromSnakeCase already mapped full_name → fullName; `private` and
    // `owner` are single words and pass through unchanged.
    enum CodingKeys: String, CodingKey {
        case fullName
        case name
        case isPrivate = "private"
        case owner
    }

    private enum OwnerKeys: String, CodingKey {
        case login
    }

    init(fullName: String, name: String?, isPrivate: Bool?, ownerLogin: String?) {
        self.fullName = fullName
        self.name = name
        self.isPrivate = isPrivate
        self.ownerLogin = ownerLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try container.decode(String.self, forKey: .fullName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
        if let ownerContainer = try? container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner) {
            ownerLogin = try ownerContainer.decodeIfPresent(String.self, forKey: .login)
        } else {
            ownerLogin = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fullName, forKey: .fullName)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(isPrivate, forKey: .isPrivate)
        if let ownerLogin {
            var ownerContainer = container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner)
            try ownerContainer.encode(ownerLogin, forKey: .login)
        }
    }
}

/// Derived metadata attached to a `source == "github"` list by `GET /api/lists`.
/// `refreshStatus` values seen from the backend: "idle", "pending", "failed"
/// (also tolerate "syncing"/"error" from other deployments). All fields optional
/// so a list serialized without this block still decodes.
struct GitHubListMeta: Codable, Hashable {
    let lastRefreshedAt: String?
    let refreshStatus: String?
    let refreshError: String?
}

/// A single GitHub issue from `GET /api/github/issues` (raw GitHub REST array).
/// Only the fields the read-only issues view needs; decode defensively.
/// `html_url` arrives as `htmlUrl` after the client's convertFromSnakeCase.
struct GitHubIssue: Codable, Identifiable, Hashable {
    let number: Int
    let title: String
    let state: String?
    let htmlUrl: String?

    var id: Int { number }
}
