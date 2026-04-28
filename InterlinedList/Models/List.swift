//
//  List.swift
//  InterlinedList
//

import Foundation

struct UserList: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let folderId: String?
    let createdAt: String
    let updatedAt: String?
    let itemCount: Int?
}

struct ListFolder: Identifiable, Codable {
    let id: String
    let name: String
    let parentId: String?
    let createdAt: String?
}

struct ListItem: Identifiable, Codable {
    let id: String
    let content: String
    let checked: Bool?
    let order: Int?
    let createdAt: String?
}

// MARK: - Tree node

struct ListTreeNode: Identifiable {
    let id: String
    let name: String
    var children: [ListTreeNode]?  // nil = list leaf, non-nil = folder
    let list: UserList?

    static func buildTree(folders: [ListFolder], lists: [UserList]) -> [ListTreeNode] {
        func folderNode(_ folder: ListFolder) -> ListTreeNode {
            let childFolders = folders
                .filter { !($0.parentId ?? "").isEmpty && $0.parentId == folder.id }
                .map { folderNode($0) }
            let childLists = lists
                .filter { !($0.folderId ?? "").isEmpty && $0.folderId == folder.id }
                .map { listNode($0) }
            let children = childFolders + childLists
            return ListTreeNode(id: folder.id, name: folder.name, children: children, list: nil)
        }

        func listNode(_ list: UserList) -> ListTreeNode {
            ListTreeNode(id: list.id, name: list.name, children: nil, list: list)
        }

        // Treat nil and empty-string the same — some API implementations send "" instead of null.
        let rootFolders = folders.filter { ($0.parentId ?? "").isEmpty }.map { folderNode($0) }
        let rootLists = lists.filter { ($0.folderId ?? "").isEmpty }.map { listNode($0) }
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

struct ListItemsResponse: Decodable {
    let items: [ListItem]
}
