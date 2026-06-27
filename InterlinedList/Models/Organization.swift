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
