//
//  Organization.swift
//  InterlinedList
//

import Foundation

/// Organization membership roles, in ascending privilege order.
enum OrgRole: String, Codable, CaseIterable, Comparable {
    case member
    case admin
    case owner

    var label: String {
        switch self {
        case .member: return "Member"
        case .admin: return "Admin"
        case .owner: return "Owner"
        }
    }

    private var rank: Int {
        switch self {
        case .member: return 0
        case .admin: return 1
        case .owner: return 2
        }
    }

    static func < (lhs: OrgRole, rhs: OrgRole) -> Bool { lhs.rank < rhs.rank }
}

struct Organization: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let isPublic: Bool?
    let avatar: String?
    let memberCount: Int?
    /// The current user's role within this org, when known ("owner"/"admin"/"member").
    let userRole: String?
    let slug: String?
    let createdAt: String?

    var role: OrgRole? { userRole.flatMap { OrgRole(rawValue: $0) } }

    init(id: String, name: String, description: String? = nil, isPublic: Bool? = nil,
         avatar: String? = nil, memberCount: Int? = nil, userRole: String? = nil,
         slug: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.isPublic = isPublic
        self.avatar = avatar
        self.memberCount = memberCount
        self.userRole = userRole
        self.slug = slug
        self.createdAt = createdAt
    }
}

struct OrganizationMember: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
    let emailVerified: Bool?
    let role: String
    let active: Bool?
    let joinedAt: String?

    var orgRole: OrgRole? { OrgRole(rawValue: role) }
    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

// MARK: - API response wrappers

struct OrganizationsResponse: Decodable {
    let organizations: [Organization]
    let pagination: Pagination?
}

struct OrganizationResponse: Decodable {
    let organization: Organization
}

struct OrganizationMembersResponse: Decodable {
    let members: [OrganizationMember]
    let pagination: Pagination?
}

/// A candidate for membership, returned by the owner-gated user search.
/// Deliberately not `User`: the search route selects a narrow column set, and
/// `email` is absent for callers that lack the privilege to see it.
struct OrganizationUser: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String?
    let email: String?
    let avatar: String?

    var displayNameOrUsername: String {
        displayName?.isEmpty == false ? (displayName ?? username) : username
    }
}

struct OrganizationUsersResponse: Decodable {
    let users: [OrganizationUser]
    let total: Int?
    // This endpoint's `pagination` block is { limit, offset, hasMore } — `total`
    // sits at the top level instead — so it does not fit the shared `Pagination`
    // type, whose `total` is required. Decoding it as one would throw.
}
