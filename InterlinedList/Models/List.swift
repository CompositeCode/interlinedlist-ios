//
//  List.swift
//  InterlinedList
//

import Foundation

// MARK: - JSON value type for dynamic rowData fields

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "Yes" : "No"
        case .null: return ""
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if c.decodeNil() { self = .null; return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value type"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - List property schema

struct ListPropertyDef: Codable, Identifiable {
    let id: String
    let propertyKey: String
    let propertyName: String
    let propertyType: String
    let displayOrder: Int
    let isVisible: Bool
    let isRequired: Bool
    let defaultValue: String?
    let helpText: String?
    let placeholder: String?
}

struct ListDetailData: Decodable {
    let id: String
    let title: String
    let properties: [ListPropertyDef]
}

struct ListDetailResponse: Decodable {
    let data: ListDetailData
}

// MARK: - Core list models

struct UserList: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let folderId: String?
    let isPublic: Bool?
    let createdAt: String
    let updatedAt: String?
    let itemCount: Int?

    // Server sends "title" for name and "parentId" for the list-in-list hierarchy.
    // convertFromSnakeCase is bypassed when CodingKeys are present, so use exact JSON keys.
    enum CodingKeys: String, CodingKey {
        case id, description, createdAt, updatedAt, itemCount, isPublic
        case name = "title"
        case folderId = "parentId"
    }
}

struct ListFolder: Identifiable, Codable {
    let id: String
    let name: String
    let parentId: String?
    let createdAt: String?
}

struct ListItem: Identifiable, Codable {
    let id: String
    let rowData: [String: JSONValue]
    let rowNumber: Int?
    let createdAt: String?
}

// MARK: - Tree node

struct ListTreeNode: Identifiable {
    let id: String
    let name: String
    var children: [ListTreeNode]?  // nil = list leaf, non-nil = folder
    let list: UserList?

    static func buildTree(folders: [ListFolder], lists: [UserList]) -> [ListTreeNode] {
        let knownFolderIds = Set(folders.map { $0.id })
        let knownListIds = Set(lists.map { $0.id })

        func folderNode(_ folder: ListFolder) -> ListTreeNode {
            let childFolders = folders
                .filter { !($0.parentId ?? "").isEmpty && $0.parentId == folder.id }
                .map { folderNode($0) }
            let childLists = lists
                .filter { !($0.folderId ?? "").isEmpty && $0.folderId == folder.id }
                .map { listNode($0) }
            return ListTreeNode(id: folder.id, name: folder.name, children: childFolders + childLists, list: nil)
        }

        // Builds a node for a list, recursing into child lists (parentId → this list's id).
        // API data is assumed acyclic; guard against any circular edge by ignoring a child
        // whose id equals the ancestor's id.
        func listNode(_ list: UserList) -> ListTreeNode {
            let children = lists.filter { child in
                guard let pid = child.folderId, !pid.isEmpty else { return false }
                return pid == list.id && child.id != list.id
            }.map { listNode($0) }
            return ListTreeNode(id: list.id, name: list.name,
                                children: children.isEmpty ? nil : children,
                                list: list)
        }

        let rootFolders = folders.filter { ($0.parentId ?? "").isEmpty }.map { folderNode($0) }
        // Root lists: no parentId, orphaned parent (parent not in this response),
        // or parentId points to a folder (handled by folderNode above).
        let rootLists = lists.filter {
            let fid = $0.folderId ?? ""
            if fid.isEmpty { return true }
            if knownFolderIds.contains(fid) { return false }
            return !knownListIds.contains(fid)
        }.map { listNode($0) }
        return rootFolders + rootLists
    }
}

// MARK: - API response wrappers

struct ListsResponse: Decodable {
    let lists: [UserList]
}

struct FoldersResponse: Decodable {
    let folders: [ListFolder]
}

// MARK: - List connections

struct ListConnection: Identifiable, Codable {
    let id: String
    let sourceListId: String
    let targetListId: String
    let createdAt: String?
}

struct ConnectionsResponse: Decodable {
    let connections: [ListConnection]
}
