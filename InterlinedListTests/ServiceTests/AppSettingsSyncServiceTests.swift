import XCTest
@testable import InterlinedList

@MainActor
final class AppSettingsSyncServiceTests: XCTestCase {
    var session: MockURLSession!
    var api: APIClient!
    var sut: AppSettingsSyncService!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        api = APIClient(session: session)
        api.setBearerToken("tok")
        sut = AppSettingsSyncService(api: api)
    }

    private func doc(version: Int, theme: String = "dark") -> String {
        #"""
        {"appKey":"il-ios","scope":"account","deviceId":null,"version":\#(version),
         "updatedAt":"2026-09-15T10:00:00.000Z","schemaVersion":1,
         "settings":{"theme":"\#(theme)"}}
        """#
    }

    // MARK: Reading

    func test_loadSharedSettings_readsTheAccountDocumentAndRemembersItsVersion() async {
        session.stub(json: doc(version: 6, theme: "light"))
        let settings = await sut.loadSharedSettings()
        XCTAssertEqual(settings?.theme, "light")
        XCTAssertEqual(sut.lastSyncedVersion, 6)
    }

    func test_loadSharedSettings_fallsBackToBootstrapOnAFreshInstall() async {
        // No account document yet…
        session.enqueue(json: #"{"error":"not_found"}"#, statusCode: 404)
        // …so provenance comes from bootstrap.
        session.enqueue(json: #"{"source":"default-device","version":2,"schemaVersion":1,"settings":{"theme":"dark"}}"#)
        let settings = await sut.loadSharedSettings()
        XCTAssertEqual(settings?.theme, "dark", "A fresh install must start from bootstrap")
        XCTAssertEqual(sut.lastSyncedVersion, 2)
    }

    func test_loadSharedSettings_isNilWhenTheAccountHasNeverSynced() async {
        session.stub(json: #"{"source":"none"}"#, statusCode: 404)
        let settings = await sut.loadSharedSettings()
        XCTAssertNil(settings)
    }

    // MARK: Writing / CAS

    func test_save_sendsTheLastReadVersionAsBaseVersion() async throws {
        session.stub(json: doc(version: 6))
        _ = await sut.loadSharedSettings()

        session.stub(json: doc(version: 7))
        let ok = await sut.save(AppSharedSettings(theme: "light"))
        XCTAssertTrue(ok)
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["baseVersion"] as? Int, 6)
        XCTAssertEqual(sut.lastSyncedVersion, 7, "The new version must be retained for the next write")
    }

    func test_save_onAFreshAccountUsesBaseVersionZero() async throws {
        session.stub(json: doc(version: 1))
        _ = await sut.save(AppSharedSettings(theme: "dark"))
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["baseVersion"] as? Int, 0)
    }

    func test_save_resolvesAConflictByReReadingAndRetrying() async {
        // First write loses the race…
        session.enqueue(json: #"{"error":"version_conflict"}"#, statusCode: 409)
        // …re-read picks up the winner's version…
        session.enqueue(json: doc(version: 9))
        // …and the retry succeeds.
        session.enqueue(json: doc(version: 10))

        let ok = await sut.save(AppSharedSettings(theme: "light"))
        XCTAssertTrue(ok, "A concurrent write must be resolved by re-reading, not clobbered")
        XCTAssertEqual(sut.lastSyncedVersion, 10)
    }

    func test_save_givesUpAfterASecondConflictRatherThanSpinning() async {
        session.enqueue(json: #"{"error":"version_conflict"}"#, statusCode: 409)
        session.enqueue(json: doc(version: 9))
        session.enqueue(json: #"{"error":"version_conflict"}"#, statusCode: 409)
        let ok = await sut.save(AppSharedSettings(theme: "light"))
        XCTAssertFalse(ok)
    }

    func test_save_refusesAnOversizedDocument() async {
        let huge = AppSharedSettings(theme: String(repeating: "x", count: AppSettingsKey.maxSettingsBytes + 1))
        let ok = await sut.save(huge)
        XCTAssertFalse(ok)
        XCTAssertNil(session.lastRequest, "The cap is enforced before anything is sent")
    }

    // MARK: The account/device split

    func test_sharedSettings_carriesAccountLevelPreferencesOnly() {
        let user = User(
            id: "u1", email: "a@b.com", username: "alice", displayName: nil, avatar: nil,
            bio: nil, theme: "dark", emailVerified: true, createdAt: nil,
            maxMessageLength: 666, showAdvancedPostSettings: true,
            defaultPubliclyVisible: false, customerStatus: "subscriber",
            githubDefaultRepo: "o/r", isPrivateAccount: true,
            viewingPreference: "following_only", messagesPerPage: 25,
            showPreviews: false, notificationTrayLimit: 30
        )
        let shared = AppSettingsSyncService.sharedSettings(from: user)
        XCTAssertEqual(shared.theme, "dark")
        XCTAssertEqual(shared.defaultPubliclyVisible, false)
        XCTAssertEqual(shared.showAdvancedPostSettings, true)
        XCTAssertEqual(shared.viewingPreference, "following_only")
        XCTAssertEqual(shared.messagesPerPage, 25)
        XCTAssertEqual(shared.showPreviews, false)
        XCTAssertEqual(shared.notificationTrayLimit, 30)
    }

    func test_sharedSettingsStayWellUnderTheSizeCap() throws {
        let settings = AppSharedSettings(
            theme: "dark", defaultPubliclyVisible: true, showAdvancedPostSettings: true,
            viewingPreference: "all_messages", messagesPerPage: 30,
            showPreviews: true, notificationTrayLimit: 40
        )
        let bytes = try JSONEncoder().encode(settings).count
        XCTAssertLessThan(bytes, 1024, "The shared document is preferences only — never cached content")
    }

    // MARK: Devices

    func test_loadDevices_publishesTheList() async {
        session.stub(json: #"{"devices":[{"deviceId":"d1","deviceName":"iPhone","platform":"ios","isDefault":true,"lastSeenAt":"2026-09-15T10:00:00.000Z","appVersion":null,"osVersion":null}]}"#)
        await sut.loadDevices()
        XCTAssertEqual(sut.devices.count, 1)
        XCTAssertEqual(sut.devices.first?.deviceName, "iPhone")
    }

    func test_loadDevices_failureLeavesAnEmptyListRatherThanThrowing() async {
        session.stub(data: Data(), statusCode: 500)
        await sut.loadDevices()
        XCTAssertTrue(sut.devices.isEmpty)
    }
}
