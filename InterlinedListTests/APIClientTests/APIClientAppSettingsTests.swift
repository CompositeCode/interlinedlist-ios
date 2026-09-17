import XCTest
@testable import InterlinedList

final class APIClientAppSettingsTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func bodyJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(session.lastRequest?.httpBody)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let docJSON = #"""
    {"appKey":"il-ios","scope":"account","deviceId":null,"version":4,
     "updatedAt":"2026-09-15T10:00:00.000Z","schemaVersion":1,
     "settings":{"theme":"dark","defaultPubliclyVisible":true,"messagesPerPage":20}}
    """#

    // MARK: Account document

    func test_appSettings_getsTheAppKeyedPath() async throws {
        session.stub(json: docJSON)
        _ = try await sut.appSettings(AppSharedSettings.self)
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios")
    }

    func test_appSettings_decodesTheDocument() async throws {
        session.stub(json: docJSON)
        let fetched = try await sut.appSettings(AppSharedSettings.self)
        let doc = try XCTUnwrap(fetched)
        XCTAssertEqual(doc.version, 4)
        XCTAssertEqual(doc.schemaVersion, 1)
        XCTAssertEqual(doc.settings.theme, "dark")
        XCTAssertEqual(doc.settings.messagesPerPage, 20)
    }

    func test_appSettings_404_isNilNotAnError() async throws {
        session.stub(json: #"{"error":"not_found"}"#, statusCode: 404)
        let doc = try await sut.appSettings(AppSharedSettings.self)
        XCTAssertNil(doc, "A fresh account has no document — that is not a failure")
    }

    func test_putAppSettings_sendsBaseVersionAndSchemaVersion() async throws {
        session.stub(json: docJSON)
        _ = try await sut.putAppSettings(AppSharedSettings(theme: "light"), baseVersion: 3)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        let json = try bodyJSON()
        XCTAssertEqual(json["baseVersion"] as? Int, 3, "CAS depends on the base version")
        XCTAssertEqual(json["schemaVersion"] as? Int, AppSettingsKey.schemaVersion)
        let settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertEqual(settings["theme"] as? String, "light")
    }

    func test_putAppSettings_409_throwsVersionConflict() async throws {
        session.stub(json: #"{"error":"version_conflict"}"#, statusCode: 409)
        do {
            _ = try await sut.putAppSettings(AppSharedSettings(theme: "dark"), baseVersion: 1)
            XCTFail("Expected a conflict")
        } catch is SettingsVersionConflict<AppSharedSettings> {
            // expected
        }
    }

    func test_putAppSettings_refusesAnOversizedDocumentBeforeSending() async throws {
        session.stub(json: docJSON)
        let huge = AppSharedSettings(theme: String(repeating: "x", count: AppSettingsKey.maxSettingsBytes + 1))
        do {
            _ = try await sut.putAppSettings(huge, baseVersion: 0)
            XCTFail("Expected a local size failure")
        } catch APIError.server(let message) {
            XCTAssertTrue(message.contains("limit"), message)
            XCTAssertNil(session.lastRequest, "An oversized document must not reach the wire")
        }
    }

    func test_deleteAppSettings_sendsDelete() async throws {
        session.stub(json: #"{"deleted":true}"#)
        try await sut.deleteAppSettings()
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios")
    }

    // MARK: Bootstrap

    func test_bootstrap_getsTheBootstrapPathAndDecodes() async throws {
        session.stub(json: #"""
        {"source":"default-device","version":2,"schemaVersion":1,
         "settings":{"theme":"dark"},"defaultDeviceId":"d1","defaultDeviceName":"Adron's iPhone"}
        """#)
        let fetched = try await sut.appSettingsBootstrap(AppSharedSettings.self)
        let bootstrap = try XCTUnwrap(fetched)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios/bootstrap")
        XCTAssertEqual(bootstrap.source, "default-device")
        XCTAssertEqual(bootstrap.settings?.theme, "dark")
        XCTAssertEqual(bootstrap.defaultDeviceName, "Adron's iPhone")
    }

    func test_bootstrap_404_isNil() async throws {
        session.stub(json: #"{"source":"none"}"#, statusCode: 404)
        let bootstrap = try await sut.appSettingsBootstrap(AppSharedSettings.self)
        XCTAssertNil(bootstrap)
    }

    // MARK: Devices

    func test_registerAppDevice_sendsCamelCaseBodyWithIosPlatform() async throws {
        session.stub(json: #"{"device":{"deviceId":"d1","deviceName":"iPhone","platform":"ios","isDefault":false,"lastSeenAt":"2026-09-15T10:00:00.000Z","appVersion":"1.0","osVersion":"18.0"}}"#)
        let device = try await sut.registerAppDevice(
            deviceId: "d1", deviceName: "iPhone", appVersion: "1.0", osVersion: "18.0"
        )
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios/devices")
        let json = try bodyJSON()
        XCTAssertEqual(json["deviceId"] as? String, "d1")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["appVersion"] as? String, "1.0")
        XCTAssertNil(json["device_id"], "Body must NOT use snake_case")
        XCTAssertEqual(device.deviceName, "iPhone")
    }

    func test_appDevices_decodesTheList() async throws {
        session.stub(json: #"{"devices":[{"deviceId":"d1","deviceName":"iPhone","platform":"ios","isDefault":true,"lastSeenAt":"2026-09-15T10:00:00.000Z","appVersion":null,"osVersion":null}]}"#)
        let devices = try await sut.appDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.id, "d1")
        XCTAssertEqual(devices.first?.isDefault, true)
    }

    func test_renameAppDevice_patchesTheDevicePath() async throws {
        session.stub(json: #"{"device":{"deviceId":"d1","deviceName":"Work phone","platform":"ios","isDefault":false,"lastSeenAt":"2026-09-15T10:00:00.000Z","appVersion":null,"osVersion":null}}"#)
        _ = try await sut.renameAppDevice(deviceId: "d1", deviceName: "Work phone")
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios/devices/d1")
        XCTAssertEqual(try bodyJSON()["deviceName"] as? String, "Work phone")
    }

    func test_forgetAppDevice_deletesTheDevicePath() async throws {
        session.stub(json: #"{"deleted":true}"#)
        try await sut.forgetAppDevice(deviceId: "d1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios/devices/d1")
    }

    // MARK: Per-device document

    func test_deviceSettings_usesTheDeviceScopedPath() async throws {
        session.stub(json: docJSON)
        _ = try await sut.appDeviceSettings(deviceId: "d1", AppSharedSettings.self)
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/user/app-settings/il-ios/devices/d1/settings")
    }

    func test_putDeviceSettings_sendsCasEnvelope() async throws {
        session.stub(json: docJSON)
        _ = try await sut.putAppDeviceSettings(deviceId: "d1", settings: AppSharedSettings(theme: "dark"), baseVersion: 2)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(try bodyJSON()["baseVersion"] as? Int, 2)
    }
}
