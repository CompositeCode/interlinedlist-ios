import XCTest
@testable import InterlinedList

final class GapModelsTests: XCTestCase {

    // MARK: - ListSchemaDraft structured serialization (B0)

    func test_slugifyKey_producesSnakeCase() {
        XCTAssertEqual(ListSchemaDraft.slugifyKey("Have Read?"), "have_read")
        XCTAssertEqual(ListSchemaDraft.slugifyKey("Title"), "title")
        XCTAssertEqual(ListSchemaDraft.slugifyKey("  Multi   Word  "), "multi_word")
        XCTAssertEqual(ListSchemaDraft.slugifyKey("!!!"), "field")
    }

    func test_structuredProperties_newPropertyOmitsIdAndSlugsKey() {
        let drafts = [DraftProperty.newBlank()]
        var draft = drafts[0]
        draft.propertyName = "Author Name"
        let result = ListSchemaDraft.structuredProperties([draft])
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].id, "New properties must omit id so the server creates them")
        XCTAssertEqual(result[0].propertyKey, "author_name")
        XCTAssertEqual(result[0].displayOrder, 0)
    }

    func test_structuredProperties_existingKeepsIdAndKey() {
        let def = ListPropertyDef(id: "p1", propertyKey: "title", propertyName: "Title", propertyType: "text", displayOrder: 0, isVisible: true, isRequired: true, defaultValue: nil, helpText: nil, placeholder: nil)
        let result = ListSchemaDraft.structuredProperties([DraftProperty(from: def)])
        XCTAssertEqual(result[0].id, "p1")
        XCTAssertEqual(result[0].propertyKey, "title")
    }

    func test_structuredProperties_dropsEmptyNamesAndRenumbersOrder() {
        var blank = DraftProperty.newBlank()
        blank.propertyName = "   "
        let def = ListPropertyDef(id: "p2", propertyKey: "year", propertyName: "Year", propertyType: "number", displayOrder: 5, isVisible: true, isRequired: false, defaultValue: nil, helpText: nil, placeholder: nil)
        let result = ListSchemaDraft.structuredProperties([blank, DraftProperty(from: def)])
        XCTAssertEqual(result.count, 1, "Empty-named drafts are dropped (soft-delete)")
        XCTAssertEqual(result[0].displayOrder, 1, "displayOrder follows array index, not the original")
    }

    // MARK: - WatcherRole

    func test_watcherRole_ordering_and_capabilities() {
        XCTAssertTrue(WatcherRole.manager > WatcherRole.collaborator)
        XCTAssertTrue(WatcherRole.collaborator > WatcherRole.watcher)
        XCTAssertFalse(WatcherRole.watcher.canEditRows)
        XCTAssertTrue(WatcherRole.collaborator.canEditRows)
        XCTAssertTrue(WatcherRole.manager.canManage)
        XCTAssertFalse(WatcherRole.collaborator.canManage)
    }

    // MARK: - OrgRole

    func test_orgRole_ordering() {
        XCTAssertTrue(OrgRole.owner > OrgRole.admin)
        XCTAssertTrue(OrgRole.admin > OrgRole.member)
        XCTAssertEqual(OrgRole(rawValue: "owner"), .owner)
        XCTAssertNil(OrgRole(rawValue: "bogus"))
    }

    // MARK: - NotificationPreference channel support

    func test_notificationPreference_supportFlags() {
        let pushOnly = NotificationPreference(key: "follow", label: "Follow", description: nil, channels: NotificationChannels(push: true, inApp: nil))
        XCTAssertTrue(pushOnly.supportsPush)
        XCTAssertFalse(pushOnly.supportsInApp)

        let both = NotificationPreference(key: "dig", label: "Dig", description: nil, channels: NotificationChannels(push: false, inApp: true))
        XCTAssertTrue(both.supportsPush)
        XCTAssertTrue(both.supportsInApp)
    }

    // MARK: - FollowUser display

    func test_followUser_displayNameFallsBackToUsername() {
        let withName = FollowUser(id: "1", username: "alice", displayName: "Alice", avatar: nil, followId: nil, status: nil, createdAt: nil)
        XCTAssertEqual(withName.displayNameOrUsername, "Alice")
        let noName = FollowUser(id: "2", username: "bob", displayName: "", avatar: nil, followId: nil, status: nil, createdAt: nil)
        XCTAssertEqual(noName.displayNameOrUsername, "bob")
    }
}
