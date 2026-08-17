import XCTest
@testable import InterlinedList

final class LinkedInTargetModelTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private func encodedJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: LinkedInTarget union encoding

    func test_encode_personal_onlyKind_noPageIds_noOrganizationId() throws {
        let json = try encodedJSON(LinkedInTarget.personal())
        XCTAssertEqual(json["kind"] as? String, "personal")
        XCTAssertNil(json["pageId"], "personal must not carry pageId")
        XCTAssertNil(json["personalPageId"], "personal must not carry personalPageId")
        XCTAssertNil(json["organizationId"], "organizationId is the outdated shape and must never be emitted")
        XCTAssertEqual(json.keys.count, 1)
    }

    func test_encode_orgPage_emitsKindAndPageId() throws {
        let json = try encodedJSON(LinkedInTarget.orgPage(pageId: "page-1"))
        XCTAssertEqual(json["kind"] as? String, "orgPage")
        XCTAssertEqual(json["pageId"] as? String, "page-1")
        XCTAssertNil(json["personalPageId"])
        XCTAssertNil(json["organizationId"])
    }

    func test_encode_personalPage_emitsKindAndPersonalPageId() throws {
        let json = try encodedJSON(LinkedInTarget.personalPage(personalPageId: "pp-9"))
        XCTAssertEqual(json["kind"] as? String, "personalPage")
        XCTAssertEqual(json["personalPageId"] as? String, "pp-9")
        XCTAssertNil(json["pageId"])
        XCTAssertNil(json["organizationId"])
    }

    // MARK: CreateMessageBody.linkedInTargets encoding

    func test_encode_messageBody_linkedInTargets_serializesToUnionKeys() throws {
        let body = CreateMessageBody(
            content: "hi", publiclyVisible: true, parentId: nil, tags: nil,
            scheduledAt: nil, imageUrls: nil, videoUrls: nil, pushedMessageId: nil,
            mastodonProviderIds: nil, crossPostToBluesky: nil, crossPostToLinkedIn: true,
            linkedInTargets: [.personal(), .orgPage(pageId: "page-1"), .personalPage(personalPageId: "pp-9")],
            linkedInLinkAsFirstComment: nil, crossPostToTwitter: nil,
            scheduledCrossPostConfig: nil, organizationId: nil)
        let json = try encodedJSON(body)
        let arr = try XCTUnwrap(json["linkedInTargets"] as? [[String: Any]])
        XCTAssertEqual(arr.count, 3)
        XCTAssertEqual(arr[0]["kind"] as? String, "personal")
        XCTAssertNil(arr[0]["pageId"])
        XCTAssertNil(arr[0]["organizationId"])
        XCTAssertEqual(arr[1]["kind"] as? String, "orgPage")
        XCTAssertEqual(arr[1]["pageId"] as? String, "page-1")
        XCTAssertEqual(arr[2]["kind"] as? String, "personalPage")
        XCTAssertEqual(arr[2]["personalPageId"] as? String, "pp-9")
        // The whole array must be free of the outdated organizationId key.
        for element in arr {
            XCTAssertNil(element["organizationId"])
        }
    }

    // MARK: LinkedInPostingTarget.asTarget mapping

    private func makeTarget(
        kind: String, pageId: String? = nil, personalPageId: String? = nil
    ) -> LinkedInPostingTarget {
        LinkedInPostingTarget(
            kind: kind, label: "L", avatarUrl: nil, pageId: pageId,
            personalPageId: personalPageId, linkedInPageId: nil, enabled: true)
    }

    func test_asTarget_personal_mapsToPersonalNoIds() {
        let t = makeTarget(kind: "personal").asTarget
        XCTAssertEqual(t.kind, "personal")
        XCTAssertNil(t.pageId)
        XCTAssertNil(t.personalPageId)
    }

    func test_asTarget_orgPage_carriesPageId() {
        let t = makeTarget(kind: "orgPage", pageId: "page-1").asTarget
        XCTAssertEqual(t.kind, "orgPage")
        XCTAssertEqual(t.pageId, "page-1")
        XCTAssertNil(t.personalPageId)
    }

    func test_asTarget_personalPage_carriesPersonalPageId() {
        let t = makeTarget(kind: "personalPage", personalPageId: "pp-9").asTarget
        XCTAssertEqual(t.kind, "personalPage")
        XCTAssertEqual(t.personalPageId, "pp-9")
        XCTAssertNil(t.pageId)
    }

    func test_asTarget_orgPageMissingPageId_fallsBackToPersonal() {
        let t = makeTarget(kind: "orgPage", pageId: nil).asTarget
        XCTAssertEqual(t.kind, "personal")
        XCTAssertNil(t.pageId)
    }

    func test_asTarget_unknownKind_fallsBackToPersonal() {
        let t = makeTarget(kind: "somethingNew").asTarget
        XCTAssertEqual(t.kind, "personal")
    }

    // MARK: LinkedInPostingTarget identity + decode

    func test_id_prefersPageIdThenPersonalPageIdThenKind() {
        XCTAssertEqual(makeTarget(kind: "orgPage", pageId: "p1").id, "p1")
        XCTAssertEqual(makeTarget(kind: "personalPage", personalPageId: "pp2").id, "pp2")
        XCTAssertEqual(makeTarget(kind: "personal").id, "personal")
    }

    func test_decode_missingOptionalFields_producesNilNotCrash() throws {
        let json = #"{"kind":"personal","label":"Me","enabled":true}"#
        let t = try JSONDecoder().decode(LinkedInPostingTarget.self, from: Data(json.utf8))
        XCTAssertEqual(t.kind, "personal")
        XCTAssertNil(t.avatarUrl)
        XCTAssertNil(t.pageId)
        XCTAssertNil(t.personalPageId)
        XCTAssertNil(t.linkedInPageId)
        XCTAssertTrue(t.enabled)
    }
}
