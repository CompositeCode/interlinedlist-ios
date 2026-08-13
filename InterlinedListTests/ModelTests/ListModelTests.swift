import XCTest
@testable import InterlinedList

final class UserListCodableTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_decode_mapsServerTitleToName() throws {
        let json = #"{"id":"1","title":"My List","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.name, "My List")
    }

    func test_decode_parentIdKey_populatesParentId_notFolderId() throws {
        // parentId is list-in-list nesting; it must NOT bleed into folderId.
        let json = #"{"id":"1","title":"L","parentId":"list-99","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.parentId, "list-99")
        XCTAssertNil(list.folderId)
    }

    func test_decode_folderIdKey_populatesFolderId() throws {
        // folderId is folder membership (backend ask A5 to surface it in the list GET).
        let json = #"{"id":"1","title":"L","folderId":"folder-7","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.folderId, "folder-7")
        XCTAssertNil(list.parentId)
    }

    func test_decode_emptyParentIdPreservedAsEmptyString() throws {
        let json = #"{"id":"1","title":"L","parentId":"","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.parentId, "")
        // The tree-builder treats "" same as nil — guard this invariant
        XCTAssertTrue((list.parentId ?? "").isEmpty)
    }
}

final class ListTreeNodeTests: XCTestCase {
    func test_buildTree_rootListWithNoFolder_appearsAtRoot() {
        let list = makeList(id: "1", folderId: nil)
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.id, "1")
    }

    func test_buildTree_listWithEmptyFolderIdAppearsAtRoot() {
        let list = makeList(id: "1", folderId: "")
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
    }

    func test_buildTree_listInFolderAppearsAsChild() {
        let folder = ListFolder(id: "f1", name: "Folder", parentId: nil, createdAt: nil)
        let list = makeList(id: "l1", folderId: "f1")
        let nodes = ListTreeNode.buildTree(folders: [folder], lists: [list])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.children?.count, 1)
        XCTAssertEqual(nodes.first?.children?.first?.id, "l1")
    }

    func test_buildTree_orphanedFolderIdAppearsAtRoot() {
        let list = makeList(id: "1", folderId: "nonexistent-folder")
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
    }

    func test_buildTree_listNestedUnderParentList() {
        let parent = makeList(id: "a")
        let child = makeList(id: "b", parentId: "a")
        let nodes = ListTreeNode.buildTree(folders: [], lists: [parent, child])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.id, "a")
        XCTAssertEqual(nodes.first?.children?.count, 1)
        XCTAssertEqual(nodes.first?.children?.first?.id, "b")
    }

    func test_buildTree_folderMembershipWinsOverParentNesting() {
        // A list with both a known folder and a parent list is rendered under the
        // folder, and must not also appear nested under its parent.
        let folder = ListFolder(id: "f1", name: "Folder", parentId: nil, createdAt: nil)
        let parent = makeList(id: "a")
        let child = makeList(id: "b", folderId: "f1", parentId: "a")
        let nodes = ListTreeNode.buildTree(folders: [folder], lists: [parent, child])
        let folderNode = nodes.first { $0.id == "f1" }
        let parentNode = nodes.first { $0.id == "a" }
        XCTAssertEqual(folderNode?.children?.first?.id, "b")
        XCTAssertNil(parentNode?.children)
    }

    private func makeList(id: String, folderId: String? = nil, parentId: String? = nil) -> UserList {
        UserList(id: id, name: "List \(id)", description: nil, parentId: parentId,
                 folderId: folderId, isPublic: nil, createdAt: "2024-01-01T00:00:00Z",
                 updatedAt: nil, itemCount: nil)
    }
}

final class JSONValueTests: XCTestCase {
    func test_displayString_string() {
        XCTAssertEqual(JSONValue.string("hello").displayString, "hello")
    }

    func test_displayString_integerNumber_noDecimal() {
        XCTAssertEqual(JSONValue.number(42).displayString, "42")
    }

    func test_displayString_fractionalNumber_showsDecimal() {
        XCTAssertEqual(JSONValue.number(3.14).displayString, "3.14")
    }

    func test_displayString_bool_true() {
        XCTAssertEqual(JSONValue.bool(true).displayString, "Yes")
    }

    func test_displayString_null_emptyString() {
        XCTAssertEqual(JSONValue.null.displayString, "")
    }
}

final class ListFolderCodableTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func test_decode_allFields() throws {
        let json = #"{"id":"f1","name":"Work","parent_id":"f0","created_at":"2024-03-15T12:00:00Z"}"#
        let folder = try decoder.decode(ListFolder.self, from: Data(json.utf8))
        XCTAssertEqual(folder.id, "f1")
        XCTAssertEqual(folder.name, "Work")
        XCTAssertEqual(folder.parentId, "f0")
        XCTAssertEqual(folder.createdAt, "2024-03-15T12:00:00Z")
    }

    func test_decode_nilParentId() throws {
        let json = #"{"id":"f2","name":"Personal","created_at":"2024-03-15T12:00:00Z"}"#
        let folder = try decoder.decode(ListFolder.self, from: Data(json.utf8))
        XCTAssertNil(folder.parentId)
    }

    func test_decode_nilCreatedAt() throws {
        let json = #"{"id":"f3","name":"Archive","parent_id":"f0"}"#
        let folder = try decoder.decode(ListFolder.self, from: Data(json.utf8))
        XCTAssertNil(folder.createdAt)
    }
}
