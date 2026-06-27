import XCTest
@testable import InterlinedList

final class ListConnectionTests: XCTestCase {
    private let decoder = JSONDecoder()

    func test_decode_listConnection_allFields() throws {
        let json = #"""
        {"id":"c1","sourceListId":"src","targetListId":"tgt","createdAt":"2024-06-01T12:00:00Z"}
        """#
        let conn = try decoder.decode(ListConnection.self, from: Data(json.utf8))
        XCTAssertEqual(conn.id, "c1")
        XCTAssertEqual(conn.sourceListId, "src")
        XCTAssertEqual(conn.targetListId, "tgt")
        XCTAssertEqual(conn.createdAt, "2024-06-01T12:00:00Z")
    }

    func test_decode_connectionsResponse_multipleItems() throws {
        let json = #"""
        {"connections":[
            {"id":"a","sourceListId":"s1","targetListId":"t1","createdAt":null},
            {"id":"b","sourceListId":"s2","targetListId":"t2","createdAt":"2024-01-01T00:00:00Z"}
        ]}
        """#
        let response = try decoder.decode(ConnectionsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.connections.count, 2)
        XCTAssertEqual(response.connections[0].id, "a")
        XCTAssertNil(response.connections[0].createdAt)
        XCTAssertEqual(response.connections[1].id, "b")
        XCTAssertEqual(response.connections[1].sourceListId, "s2")
    }
}
