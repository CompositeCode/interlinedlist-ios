//
//  APIClient+GitHub.swift
//  InterlinedList
//

import Foundation

/// GitHub repo metadata (`/api/github/*`, Bearer). These routes resolve the user
/// through `getGitHubIssuesContext`, which accepts a Bearer sync token, then call
/// GitHub with the linked account's token. They return **400 "GitHub account not
/// linked"** — not 401 — when no GitHub identity is linked, so callers should
/// degrade to free-text entry rather than treat it as an auth failure.
///
/// Issue rows themselves are still written through the standard
/// `/api/lists/:id/data` proxy (`updateItem`, full row) — never through GitHub's
/// issue routes directly — because the backend rebuilds the issue from the row it
/// receives and defaults a missing `title` to "Untitled".
extension APIClient {
    /// Labels defined on a repo (`GET /api/github/repos/:owner/:repo/labels`).
    func githubLabels(owner: String, repo: String) async throws -> [GitHubLabel] {
        try await get("/api/github/repos/\(escape(owner))/\(escape(repo))/labels")
    }

    /// Users assignable to the repo's issues
    /// (`GET /api/github/repos/:owner/:repo/assignees`).
    func githubAssignees(owner: String, repo: String) async throws -> [GitHubAssignee] {
        try await get("/api/github/repos/\(escape(owner))/\(escape(repo))/assignees")
    }

    /// Organizations the linked GitHub account belongs to (`GET /api/github/orgs`).
    /// Best-effort on the server: private memberships appear only when the
    /// connection carried the `read:org` scope.
    func githubOrgs() async throws -> [GitHubOrg] {
        let response: GitHubOrgsResponse = try await get("/api/github/orgs")
        return response.orgs
    }

    /// The number GitHub will assign to the next issue in a repo
    /// (`GET /api/github/repos/:owner/:repo/next-issue-number`).
    func githubNextIssueNumber(owner: String, repo: String) async throws -> Int {
        let response: GitHubNextIssueNumber = try await get(
            "/api/github/repos/\(escape(owner))/\(escape(repo))/next-issue-number"
        )
        return response.nextNumber
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }
}
