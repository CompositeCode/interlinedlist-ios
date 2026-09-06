import XCTest
@testable import InterlinedList

final class AIJSONTests: XCTestCase {

    private func roundTrip(_ json: String) throws -> String {
        let value = try JSONDecoder().decode(AIJSON.self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: normalized, as: UTF8.self)
    }

    private func normalize(_ json: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    func test_scalarsRoundTrip() throws {
        let json = #"{"s":"text","i":42,"d":1.5,"b":true,"n":null}"#
        XCTAssertEqual(try roundTrip(json), try normalize(json))
    }

    /// A whole number must not come back as `1.0` — the server re-parses the DSL
    /// and a float where an integer belongs changes the schema.
    func test_wholeNumbersStayIntegers() throws {
        let value = try JSONDecoder().decode(AIJSON.self, from: Data(#"{"min":1,"step":50}"#.utf8))
        XCTAssertEqual(value.objectValue?["min"], .int(1))
        let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"min\":1"))
        XCTAssertFalse(encoded.contains("1.0"))
    }

    func test_nestedObjectsAndArraysRoundTrip() throws {
        let json = #"""
        {"name":"Talks","fields":[
          {"key":"scheduled_at","type":"date","validation":{"min":1,"step":1}},
          {"key":"status","type":"select","options":["Draft","Published"]},
          {"key":"blocked_by","visibility":{"condition":{"field":"status","operator":"equals","value":"Blocked"}}}
        ]}
        """#
        XCTAssertEqual(try roundTrip(json), try normalize(json))
    }

    /// Snake_case keys inside the DSL are data, not Swift property names.
    func test_snakeCaseKeysArePreserved() throws {
        let value = try JSONDecoder().decode(AIJSON.self, from: Data(#"{"scheduled_at":"2026-01-01"}"#.utf8))
        XCTAssertNotNil(value.objectValue?["scheduled_at"])
        XCTAssertNil(value.objectValue?["scheduledAt"])
        let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertTrue(encoded.contains("scheduled_at"))
    }

    func test_topLevelArrayRoundTrips() throws {
        let value = try JSONDecoder().decode(AIJSON.self, from: Data(#"[1,"two",false,null]"#.utf8))
        XCTAssertEqual(value.arrayValue?.count, 4)
        XCTAssertEqual(value.arrayValue?[0], .int(1))
        XCTAssertEqual(value.arrayValue?[3], .null)
    }

    func test_displayStringFlattensValues() {
        XCTAssertEqual(AIJSON.string("hi").displayString, "hi")
        XCTAssertEqual(AIJSON.int(3).displayString, "3")
        XCTAssertEqual(AIJSON.double(2.0).displayString, "2")
        XCTAssertEqual(AIJSON.double(2.5).displayString, "2.5")
        XCTAssertEqual(AIJSON.bool(true).displayString, "Yes")
        XCTAssertEqual(AIJSON.array([.string("a"), .string("b")]).displayString, "a, b")
        XCTAssertEqual(AIJSON.null.displayString, "")
    }
}
