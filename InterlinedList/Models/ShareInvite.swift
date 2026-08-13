//
//  ShareInvite.swift
//  InterlinedList
//

import Foundation

/// An email-bound invite to a list or document. The owner sends an invite to an
/// email address; the recipient claims it on the **web** (claim is session-only,
/// so iOS never handles the inbound side). iOS only sends, lists, and revokes
/// invites on behalf of the owner. `role` maps to `WatcherRole`, like `ShareLink`.
struct ShareInvite: Identifiable, Codable {
    let token: String
    let email: String
    let role: String
    let expiresAt: String?
    let accepted: Bool?
    let createdAt: String?

    var id: String { token }

    var shareRole: WatcherRole? { WatcherRole(rawValue: role) }
}

struct ShareInvitesResponse: Decodable {
    let invites: [ShareInvite]
}

/// The 201 response from creating an invite: `{ email, role, expiresAt, url }`.
/// Distinct from `ShareInvite` because the create route returns a claim `url`
/// (to share out-of-band) but no `token`/`accepted`/`createdAt`.
struct CreateShareInviteResponse: Decodable {
    let email: String
    let role: String
    let expiresAt: String?
    let url: String

    var shareRole: WatcherRole? { WatcherRole(rawValue: role) }
}
