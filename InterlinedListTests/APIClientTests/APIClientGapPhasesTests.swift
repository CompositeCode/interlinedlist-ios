import XCTest
@testable import InterlinedList

/// Covers the APIClient surface added for the GAP roadmap phases:
/// follow lists, list watchers, public browse, organizations, structured schema,
/// notification preferences, message search, and scheduled-message editing.
final class APIClientGapPhasesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    private func bodyString() -> String {
        String(data: session.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
    }

    // MARK: - Phase 5: Follow lists

    func test_followers_getsPaginatedList() async throws {
        session.stub(json: #"{"followers":[{"id":"u1","username":"alice","displayName":"Alice","avatar":null,"followId":"f1","status":"accepted","createdAt":"t"}],"pagination":{"total":1,"limit":30,"offset":0,"hasMore":false}}"#)
        let (users, pagination) = try await sut.followers(userId: "me")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/me/followers") == true)
        XCTAssertEqual(users.first?.username, "alice")
        XCTAssertEqual(pagination?.total, 1)
    }

    func test_following_getsPaginatedList() async throws {
        session.stub(json: #"{"following":[{"id":"u2","username":"bob","displayName":null,"avatar":null,"followId":"f2","status":"pending","createdAt":"t"}],"pagination":{"total":1,"limit":30,"offset":0,"hasMore":true}}"#)
        let (users, _) = try await sut.following(userId: "me")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/me/following") == true)
        XCTAssertEqual(users.first?.displayNameOrUsername, "bob")
    }

    func test_mutualCounts_decodes() async throws {
        session.stub(json: #"{"mutualFollowers":4,"mutualFollowing":7}"#)
        let counts = try await sut.mutualCounts(userId: "u1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1/mutual") == true)
        XCTAssertEqual(counts.mutualFollowers, 4)
        XCTAssertEqual(counts.mutualFollowing, 7)
    }

    func test_removeFollower_sendsDelete() async throws {
        session.stub(json: #"{"message":"removed"}"#)
        try await sut.removeFollower(userId: "u1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/follow/u1/remove") == true)
    }

    // MARK: - Phase 6: Watchers

    func test_listWatchers_decodesRolesAndUsers() async throws {
        session.stub(json: #"{"watchers":[{"id":"w1","userId":"u1","role":"manager","createdAt":"t","user":{"id":"u1","username":"alice","displayName":"Alice","avatar":null}}]}"#)
        let watchers = try await sut.listWatchers(listId: "l1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/watchers") == true)
        XCTAssertEqual(watchers.first?.watcherRole, .manager)
        XCTAssertEqual(watchers.first?.user?.username, "alice")
    }

    func test_isWatchingList_decodesBool() async throws {
        session.stub(json: #"{"watching":true}"#)
        let watching = try await sut.isWatchingList(listId: "l1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/watchers/me") == true)
        XCTAssertTrue(watching)
    }

    func test_addWatcher_postsUserIdAndRole() async throws {
        session.stub(json: #"{"watching":true}"#, statusCode: 201)
        let result = try await sut.addWatcher(listId: "l1", userId: "u9", role: .collaborator)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/watchers") == true)
        let body = bodyString()
        XCTAssertTrue(body.contains("u9"))
        XCTAssertTrue(body.contains("collaborator"))
        XCTAssertTrue(result)
    }

    func test_setWatcherRole_putsRole() async throws {
        session.stub(json: #"{"role":"manager"}"#)
        let role = try await sut.setWatcherRole(listId: "l1", userId: "u9", role: .manager)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/watchers/u9") == true)
        XCTAssertEqual(role, "manager")
    }

    func test_removeWatcher_sendsDelete() async throws {
        session.stub(json: #"{"removed":true}"#)
        try await sut.removeWatcher(listId: "l1", userId: "u9")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/watchers/u9") == true)
    }

    func test_searchWatcherCandidates_decodes() async throws {
        session.stub(json: #"{"users":[{"id":"u1","username":"alice","displayName":"Alice","email":"a@x.com","avatar":null}],"total":1,"pagination":{"limit":20,"offset":0,"hasMore":false}}"#)
        let users = try await sut.searchWatcherCandidates(listId: "l1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/watchers/users") == true)
        XCTAssertEqual(users.first?.email, "a@x.com")
    }

    // MARK: - B0: Structured schema

    func test_updateListSchemaStructured_putsPropertiesArray() async throws {
        session.stub(json: #"{"properties":[{"id":"p1","propertyKey":"title","propertyName":"Title","propertyType":"text","displayOrder":0,"isVisible":true,"isRequired":true,"defaultValue":null,"helpText":null,"placeholder":null}]}"#)
        let input = [SchemaPropertyInput(id: "p1", propertyKey: "title", propertyName: "Title", propertyType: "text", displayOrder: 0, isVisible: true, isRequired: true, defaultValue: nil, helpText: nil, placeholder: nil)]
        let props = try await sut.updateListSchemaStructured(listId: "l1", properties: input)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/lists/l1/schema") == true)
        XCTAssertTrue(bodyString().contains("properties"))
        XCTAssertEqual(props.first?.propertyKey, "title")
    }

    func test_updateListSchemaStructured_force_addsQueryParam() async throws {
        session.stub(json: #"{"properties":[]}"#)
        _ = try await sut.updateListSchemaStructured(listId: "l1", properties: [], force: true)
        XCTAssertTrue(session.lastRequest?.url?.query?.contains("force=true") == true)
    }

    func test_updateListSchemaStructured_409_throwsConflict() async throws {
        session.stub(json: #"{"error":"column has data"}"#, statusCode: 409)
        do {
            _ = try await sut.updateListSchemaStructured(listId: "l1", properties: [])
            XCTFail("Expected conflict")
        } catch APIError.conflict(let msg) {
            XCTAssertEqual(msg, "column has data")
        }
    }

    // MARK: - Phase 7: Public browse

    func test_publicListDetail_flatShape_decodes() async throws {
        session.stub(json: #"{"id":"l1","title":"Books","description":"d","isPublic":true,"schema":"Title:text","owner":{"username":"alice","displayName":"Alice"}}"#)
        let detail = try await sut.publicListDetail(username: "alice", listId: "l1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/users/alice/lists/l1") == true)
        XCTAssertEqual(detail.title, "Books")
        XCTAssertEqual(detail.owner?.username, "alice")
    }

    func test_publicListDetail_wrappedShape_decodes() async throws {
        session.stub(json: #"{"list":{"id":"l1","title":"Books","children":[{"id":"l2","title":"Sub"}]},"ancestors":[{"id":"root","title":"Root"}]}"#)
        let detail = try await sut.publicListDetail(username: "alice", listId: "l1")
        XCTAssertEqual(detail.title, "Books")
        XCTAssertEqual(detail.children?.first?.id, "l2")
        XCTAssertEqual(detail.ancestors?.first?.title, "Root")
    }

    func test_publicListData_decodesRows() async throws {
        session.stub(json: #"{"rows":[{"id":"r1","rowData":{"title":"Dune"},"rowNumber":1,"createdAt":null}],"pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}"#)
        let data = try await sut.publicListData(username: "alice", listId: "l1")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/users/alice/lists/l1/data") == true)
        XCTAssertEqual(data.rows.count, 1)
    }

    func test_publicDocuments_decodes() async throws {
        session.stub(json: #"{"documents":[{"id":"d1","title":"Notes","folderId":null,"relativePath":"Notes","createdAt":null,"updatedAt":null}],"folders":[]}"#)
        let response = try await sut.publicDocuments(username: "alice")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/users/alice/documents") == true)
        XCTAssertEqual(response.documents.first?.title, "Notes")
    }

    func test_publicDocument_wrappedOrBare_decodes() async throws {
        session.stub(json: #"{"document":{"id":"d1","title":"Notes","content":"hello","folderId":null,"isPublic":true,"createdAt":null,"updatedAt":null}}"#)
        let doc = try await sut.publicDocument(id: "d1")
        XCTAssertEqual(doc.content, "hello")
    }

    // MARK: - Phase 8: Organizations

    func test_organizations_decodesList() async throws {
        session.stub(json: #"{"organizations":[{"id":"o1","name":"Acme"}],"pagination":null}"#)
        let (orgs, _) = try await sut.organizations()
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/organizations") == true)
        XCTAssertEqual(orgs.first?.name, "Acme")
    }

    func test_organization_decodesRole() async throws {
        session.stub(json: #"{"organization":{"id":"o1","name":"Acme","isPublic":false,"memberCount":3,"userRole":"owner"}}"#)
        let org = try await sut.organization(id: "o1")
        XCTAssertEqual(org.role, .owner)
        XCTAssertEqual(org.memberCount, 3)
    }

    func test_createOrganization_postsBody() async throws {
        session.stub(json: #"{"organization":{"id":"o1","name":"Acme"}}"#, statusCode: 201)
        _ = try await sut.createOrganization(name: "Acme", description: "d", isPublic: true)
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(bodyString().contains("Acme"))
    }

    func test_updateOrganization_putsBody() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.updateOrganization(id: "o1", name: "New", description: nil, isPublic: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/organizations/o1") == true)
    }

    func test_deleteOrganization_sendsDelete() async throws {
        session.stub(data: Data(), statusCode: 200)
        try await sut.deleteOrganization(id: "o1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE")
    }

    func test_organizationMembers_decodesRolesAndPagination() async throws {
        session.stub(json: #"{"members":[{"id":"u1","username":"alice","displayName":"Alice","avatar":null,"emailVerified":true,"role":"owner","active":true,"joinedAt":"t"}],"pagination":{"total":1,"limit":50,"offset":0,"hasMore":false}}"#)
        let (members, pagination) = try await sut.organizationMembers(id: "o1")
        XCTAssertEqual(members.first?.orgRole, .owner)
        XCTAssertEqual(pagination?.total, 1)
    }

    func test_setOrganizationMemberRole_putsRole() async throws {
        session.stub(json: #"{"ok":true}"#)
        try await sut.setOrganizationMemberRole(id: "o1", userId: "u1", role: .admin)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PUT")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/organizations/o1/members/u1") == true)
        XCTAssertTrue(bodyString().contains("admin"))
    }

    func test_joinOrganization_postsId() async throws {
        session.stub(json: #"{"ok":true}"#, statusCode: 201)
        try await sut.joinOrganization(organizationId: "o1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/user/organizations") == true)
        XCTAssertTrue(bodyString().contains("o1"))
    }

    // MARK: - Phase 12/13: Notification preferences + message search

    func test_notificationPreferences_decodesChannels() async throws {
        session.stub(json: #"{"events":[{"key":"dig","label":"Digs","description":"d","channels":{"push":true,"inApp":false}}]}"#)
        let events = try await sut.notificationPreferences()
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/user/notification-preferences") == true)
        XCTAssertEqual(events.first?.channels.push, true)
        XCTAssertEqual(events.first?.channels.inApp, false)
    }

    func test_updateNotificationPreference_patchesBody() async throws {
        session.stub(json: #"{"key":"dig","label":"Digs","description":"d","channels":{"push":false,"inApp":true}}"#)
        let updated = try await sut.updateNotificationPreference(key: "dig", channels: NotificationChannels(push: false, inApp: true))
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertTrue(bodyString().contains("dig"))
        XCTAssertEqual(updated.channels.push, false)
    }

    func test_searchMessages_getsWithQuery() async throws {
        session.stub(json: #"{"messages":[],"pagination":{"total":0,"limit":20,"offset":0,"hasMore":false}}"#)
        _ = try await sut.searchMessages(q: "swift ui")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/messages/search") == true)
        XCTAssertTrue(session.lastRequest?.url?.query?.contains("q=") == true)
    }

    // MARK: - Phase 4: Scheduled edit + cross-post

    func test_patchScheduledMessage_sendsPatch() async throws {
        session.stub(json: #"{"data":{"id":"m1","content":"hi","userId":"u1","createdAt":"t"}}"#)
        _ = try await sut.patchScheduledMessage(id: "m1", scheduledAt: "2026-07-01T10:00:00Z", config: nil)
        XCTAssertEqual(session.lastRequest?.httpMethod, "PATCH")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/messages/m1") == true)
        XCTAssertTrue(bodyString().contains("scheduledAt"))
    }

    func test_postMessage_withCrossPost_includesResults() async throws {
        session.stub(json: #"{"data":{"id":"m1","content":"hi","userId":"u1","createdAt":"t"},"crossPostResults":[{"platform":"bluesky","success":true,"error":null}]}"#, statusCode: 201)
        let result = try await sut.postMessage(content: "hi", crossPostToBluesky: true)
        XCTAssertTrue(bodyString().contains("crossPostToBluesky"))
        XCTAssertEqual(result.crossPostResults.first?.platform, "bluesky")
        XCTAssertEqual(result.crossPostResults.first?.success, true)
    }

    func test_refreshMessageMetadata_decodesLinks() async throws {
        session.stub(json: #"{"message":"ok","metadata":{"links":[{"url":"https://x.com","title":"X","description":"d","image":"i"}]}}"#)
        let links = try await sut.refreshMessageMetadata(messageId: "m1")
        XCTAssertEqual(session.lastRequest?.httpMethod, "POST")
        XCTAssertTrue(session.lastRequest?.url?.path.hasSuffix("/api/messages/m1/metadata") == true)
        XCTAssertEqual(links.first?.title, "X")
    }
}
