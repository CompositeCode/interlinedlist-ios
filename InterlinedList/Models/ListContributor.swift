//
//  ListContributor.swift
//  InterlinedList
//

import Foundation

/// A person who has actually written rows into a list, aggregated by the backend
/// across every row's created-by / last-edited-by attribution.
///
/// Distinct from `ListWatcher`: a watcher has been *granted* access, a
/// contributor has *used* it. On a shared list the latter is the more useful
/// signal, which is why the web surfaces it on the list header.
struct ListContributor: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
    /// Rows this person created.
    let addedCount: Int
    /// Rows this person was the last to edit.
    let editedCount: Int
    /// `addedCount + editedCount` — the server's ranking key.
    let score: Int

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }

    /// Matches the web's contributor subtitle: "added 4 · edited 2".
    var contributionSummary: String {
        "added \(addedCount) · edited \(editedCount)"
    }
}

/// `GET /api/lists/{id}/contributors` — the **full** ranked set with no server
/// paging, so `totalContributors` always equals `contributors.count`. It is
/// decoded anyway because it is what the web's "+N" overflow bubble counts
/// against, and trusting the server's own total keeps iOS and web in step.
struct ListContributorsResult: Decodable {
    let contributors: [ListContributor]
    let totalContributors: Int

    static let empty = ListContributorsResult(contributors: [], totalContributors: 0)

    init(contributors: [ListContributor], totalContributors: Int) {
        self.contributors = contributors
        self.totalContributors = totalContributors
    }
}
