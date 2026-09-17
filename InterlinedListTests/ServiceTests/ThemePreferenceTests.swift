import XCTest
import SwiftUI
@testable import InterlinedList

final class ThemePreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "ThemePreferenceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Parsing

    func test_init_stored_knownValues_parse() {
        XCTAssertEqual(ThemePreference(stored: "system"), .system)
        XCTAssertEqual(ThemePreference(stored: "light"), .light)
        XCTAssertEqual(ThemePreference(stored: "dark"), .dark)
    }

    func test_init_stored_mixedCase_parses() {
        XCTAssertEqual(ThemePreference(stored: "Dark"), .dark)
    }

    func test_init_stored_nil_fallsBackToSystem() {
        XCTAssertEqual(ThemePreference(stored: nil), .system)
    }

    func test_init_stored_unknownValue_fallsBackToSystem() {
        XCTAssertEqual(ThemePreference(stored: "sepia"), .system)
        XCTAssertEqual(ThemePreference(stored: ""), .system)
    }

    func test_colorScheme_mapsEachCase() {
        XCTAssertNil(ThemePreference.system.colorScheme)
        XCTAssertEqual(ThemePreference.light.colorScheme, ColorScheme.light)
        XCTAssertEqual(ThemePreference.dark.colorScheme, ColorScheme.dark)
    }

    // MARK: - Resolution (server value vs. mirror)

    func test_resolve_serverThemePresent_winsOverMirror() {
        XCTAssertEqual(ThemePreference.resolve(serverTheme: "light", mirrored: "dark"), .light)
    }

    func test_resolve_serverThemeMissing_usesMirror() {
        // The login screen and every cold launch before GET /api/user answers.
        XCTAssertEqual(ThemePreference.resolve(serverTheme: nil, mirrored: "dark"), .dark)
    }

    func test_resolve_serverThemeUnknown_fallsBackToSystemNotMirror() {
        XCTAssertEqual(ThemePreference.resolve(serverTheme: "chartreuse", mirrored: "dark"), .system)
    }

    func test_resolve_bothMissing_isSystem() {
        XCTAssertEqual(ThemePreference.resolve(serverTheme: nil, mirrored: nil), .system)
    }

    // MARK: - Mirror persistence

    func test_current_nothingStored_isSystem() {
        XCTAssertEqual(ThemePreferenceStore(defaults: defaults).current, .system)
    }

    func test_save_thenFreshStore_readsStoredValue() throws {
        ThemePreferenceStore(defaults: defaults).save("dark")

        let reopened = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(ThemePreferenceStore(defaults: reopened).current, .dark)
    }

    func test_save_unknownValue_normalizesToSystem() {
        let store = ThemePreferenceStore(defaults: defaults)
        store.save("dark")
        store.save("sepia")
        XCTAssertEqual(store.current, .system)
    }

    func test_save_nil_normalizesToSystem() {
        let store = ThemePreferenceStore(defaults: defaults)
        store.save("dark")
        store.save(nil)
        XCTAssertEqual(store.current, .system)
    }

    func test_save_writesRawValueUnderSharedKey() {
        // RootView reads the same key through @AppStorage, so the raw string matters.
        ThemePreferenceStore(defaults: defaults).save("light")
        XCTAssertEqual(defaults.string(forKey: ThemePreference.storageKey), "light")
    }
}
