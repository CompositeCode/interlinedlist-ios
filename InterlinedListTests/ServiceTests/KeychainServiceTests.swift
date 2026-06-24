import XCTest
@testable import InterlinedList

/// Hits the real iOS keychain on the simulator. Each test cleans up after
/// itself in both `setUp` and `tearDown` to keep the keychain in a known
/// state regardless of test ordering or prior failures.
final class KeychainServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = KeychainService.deleteToken()
    }

    override func tearDown() {
        _ = KeychainService.deleteToken()
        super.tearDown()
    }

    func test_loadToken_whenAbsent_returnsNil() {
        XCTAssertNil(KeychainService.loadToken())
    }

    func test_saveToken_thenLoad_returnsSameToken() {
        XCTAssertTrue(KeychainService.saveToken("il_tok_abc123"))
        XCTAssertEqual(KeychainService.loadToken(), "il_tok_abc123")
    }

    func test_saveToken_overwritesPriorToken() {
        XCTAssertTrue(KeychainService.saveToken("first"))
        XCTAssertTrue(KeychainService.saveToken("second"))
        XCTAssertEqual(KeychainService.loadToken(), "second")
    }

    func test_deleteToken_whenPresent_returnsTrueAndClears() {
        XCTAssertTrue(KeychainService.saveToken("to-delete"))
        XCTAssertTrue(KeychainService.deleteToken())
        XCTAssertNil(KeychainService.loadToken())
    }

    func test_deleteToken_whenAbsent_returnsTrue() {
        // Per the implementation, deleting when nothing's there is success
        // (errSecItemNotFound is treated as success so logout is idempotent).
        XCTAssertTrue(KeychainService.deleteToken())
    }

    func test_saveToken_emptyString_succeedsAndLoadsBackEmpty() {
        // The current implementation doesn't validate; document the behavior
        // here so a future stricter validation doesn't silently change it.
        XCTAssertTrue(KeychainService.saveToken(""))
        XCTAssertEqual(KeychainService.loadToken(), "")
    }

    func test_saveToken_unicodePayload_roundTrips() {
        let unicode = "il_tok_🔑✨_αβγ"
        XCTAssertTrue(KeychainService.saveToken(unicode))
        XCTAssertEqual(KeychainService.loadToken(), unicode)
    }

    func test_saveToken_longPayload_roundTrips() {
        let long = String(repeating: "a", count: 4096)
        XCTAssertTrue(KeychainService.saveToken(long))
        XCTAssertEqual(KeychainService.loadToken(), long)
    }
}
