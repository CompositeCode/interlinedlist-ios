import XCTest
@testable import InterlinedList

final class UserListCodableTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_decode_mapsServerTitleToName() throws {
        let json = #"{"id":"1","title":"My List","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.name, "My List")
    }

    func test_decode_mapsParentIdToFolderId() throws {
        let json = #"{"id":"1","title":"L","parentId":"folder-99","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.folderId, "folder-99")
    }

    func test_decode_emptyParentIdPreservedAsEmptyString() throws {
        let json = #"{"id":"1","title":"L","parentId":"","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.folderId, "")
        // The tree-builder treats "" same as nil — guard this invariant
        XCTAssertTrue((list.folderId ?? "").isEmpty)
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

    func test_buildTree_orphanedParentIdAppearsAtRoot() {
        let list = makeList(id: "1", folderId: "nonexistent-folder")
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
    }

    private func makeList(id: String, folderId: String?) -> UserList {
        UserList(id: id, name: "List \(id)", description: nil, folderId: folderId,
                 isPublic: nil, createdAt: "2024-01-01T00:00:00Z", updatedAt: nil, itemCount: nil)
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
