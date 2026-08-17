import XCTest
@testable import InterlinedList

final class ListConnectionTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_decode_listConnection_allFields() throws {
        let json = #"""
        {"id":"c1","fromListId":"src","toListId":"tgt","label":"related","createdAt":"2024-06-01T12:00:00Z"}
        """#
        let conn = try decoder.decode(ListConnection.self, from: Data(json.utf8))
        XCTAssertEqual(conn.id, "c1")
        XCTAssertEqual(conn.fromListId, "src")
        XCTAssertEqual(conn.toListId, "tgt")
        XCTAssertEqual(conn.label, "related")
        XCTAssertEqual(conn.createdAt, "2024-06-01T12:00:00Z")
    }

    func test_decode_connectionsResponse_multipleItems() throws {
        let json = #"""
        {"connections":[
            {"id":"a","fromListId":"s1","toListId":"t1","label":null,"createdAt":null},
            {"id":"b","fromListId":"s2","toListId":"t2","label":null,"createdAt":"2024-01-01T00:00:00Z"}
        ]}
        """#
        let response = try decoder.decode(ConnectionsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.connections.count, 2)
        XCTAssertEqual(response.connections[0].id, "a")
        XCTAssertNil(response.connections[0].createdAt)
        XCTAssertEqual(response.connections[1].id, "b")
        XCTAssertEqual(response.connections[1].fromListId, "s2")
    }

    // MARK: - Relationship semantics (fromList is the parent of toList)

    func test_relationship_fromListSeesOtherAsChild() {
        let conn = ListConnection(id: "c", fromListId: "A", toListId: "B", label: nil, createdAt: nil)
        XCTAssertEqual(conn.relationship(relativeTo: "A"), .child)
        XCTAssertEqual(conn.otherListId(relativeTo: "A"), "B")
    }

    func test_relationship_toListSeesOtherAsParent() {
        let conn = ListConnection(id: "c", fromListId: "A", toListId: "B", label: nil, createdAt: nil)
        XCTAssertEqual(conn.relationship(relativeTo: "B"), .parent)
        XCTAssertEqual(conn.otherListId(relativeTo: "B"), "A")
    }
}
