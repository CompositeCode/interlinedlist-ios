import XCTest
@testable import InterlinedList

final class OrganizationModelTests: XCTestCase {
    func test_decode_fullObject() throws {
        let json = #"{"id":"o1","name":"Acme","description":"Hello","isPublic":true}"#
        let org = try JSONDecoder().decode(Organization.self, from: Data(json.utf8))
        XCTAssertEqual(org.id, "o1")
        XCTAssertEqual(org.name, "Acme")
        XCTAssertEqual(org.description, "Hello")
        XCTAssertEqual(org.isPublic, true)
    }

    func test_decode_nullDescription() throws {
        let json = #"{"id":"o1","name":"Acme","description":null,"isPublic":false}"#
        let org = try JSONDecoder().decode(Organization.self, from: Data(json.utf8))
        XCTAssertNil(org.description)
        XCTAssertEqual(org.isPublic, false)
    }

    func test_decode_missingOptionalsTreatsAsNil() throws {
        let json = #"{"id":"o1","name":"Acme"}"#
        let org = try JSONDecoder().decode(Organization.self, from: Data(json.utf8))
        XCTAssertNil(org.description)
        XCTAssertNil(org.isPublic)
    }

    func test_roundTrip() throws {
        let original = Organization(id: "o1", name: "Acme", description: "x", isPublic: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Organization.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.isPublic, original.isPublic)
    }
}
