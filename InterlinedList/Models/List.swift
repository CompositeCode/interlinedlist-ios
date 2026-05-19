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
        let knownFolderIds = Set(folders.map { $0.id })

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

        let rootFolders = folders.filter { ($0.parentId ?? "").isEmpty }.map { folderNode($0) }
        // Show a list at root if it has no folderId, an empty folderId, or a folderId that
        // doesn't match any returned folder (e.g. when /api/folders silently returned []).
        let rootLists = lists.filter {
            let fid = $0.folderId ?? ""
            return fid.isEmpty || !knownFolderIds.contains(fid)
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

struct ListItemsResponse: Decodable {
    let items: [ListItem]
}
