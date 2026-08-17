import XCTest
@testable import InterlinedList

final class UserListCodableTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_decode_mapsServerTitleToName() throws {
        let json = #"{"id":"1","title":"My List","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.name, "My List")
    }

    func test_decode_parentIdKey_populatesParentId() throws {
        // parentId is list-in-list nesting.
        let json = #"{"id":"1","title":"L","parentId":"list-99","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try decoder.decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.parentId, "list-99")
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
    func test_buildTree_rootList_appearsAtRoot() {
        let list = makeList(id: "1")
        let nodes = ListTreeNode.buildTree(lists: [list])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.id, "1")
        XCTAssertNil(nodes.first?.children)
    }

    func test_buildTree_listWithEmptyParentIdAppearsAtRoot() {
        let list = makeList(id: "1", parentId: "")
        let nodes = ListTreeNode.buildTree(lists: [list])
        XCTAssertEqual(nodes.count, 1)
    }

    func test_buildTree_orphanedParentIdAppearsAtRoot() {
        // A parentId that references a list we don't have falls through to root.
        let list = makeList(id: "1", parentId: "nonexistent-list")
        let nodes = ListTreeNode.buildTree(lists: [list])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.id, "1")
    }

    func test_buildTree_listNestedUnderParentList() {
        let parent = makeList(id: "a")
        let child = makeList(id: "b", parentId: "a")
        let nodes = ListTreeNode.buildTree(lists: [parent, child])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.id, "a")
        XCTAssertEqual(nodes.first?.children?.count, 1)
        XCTAssertEqual(nodes.first?.children?.first?.id, "b")
    }

    func test_buildTree_multipleRootsPreserved() {
        let a = makeList(id: "a")
        let b = makeList(id: "b")
        let nodes = ListTreeNode.buildTree(lists: [a, b])
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(Set(nodes.map { $0.id }), ["a", "b"])
    }

    private func makeList(id: String, parentId: String? = nil) -> UserList {
        UserList(id: id, name: "List \(id)", description: nil, parentId: parentId,
                 isPublic: nil, createdAt: "2024-01-01T00:00:00Z",
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
