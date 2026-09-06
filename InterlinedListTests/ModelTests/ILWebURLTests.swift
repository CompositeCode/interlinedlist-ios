import XCTest
@testable import InterlinedList

final class ILWebURLTests: XCTestCase {

    func test_profile_buildsUserPath() {
        XCTAssertEqual(ILWebURL.profile("bob")?.absoluteString,
                       "https://interlinedlist.com/user/bob")
    }

    func test_message_buildsMessagePath() {
        XCTAssertEqual(ILWebURL.message("abc")?.absoluteString,
                       "https://interlinedlist.com/message/abc")
    }

    func test_list_buildsListsPath() {
        XCTAssertEqual(ILWebURL.list("l1")?.absoluteString,
                       "https://interlinedlist.com/lists/l1")
    }

    func test_document_buildsDocumentsPath() {
        XCTAssertEqual(ILWebURL.document("d1")?.absoluteString,
                       "https://interlinedlist.com/documents/d1")
    }

    func test_profile_percentEncodesUsername() {
        let url = ILWebURL.profile("user name")
        XCTAssertEqual(url?.absoluteString, "https://interlinedlist.com/user/user%20name")
    }

    func test_profile_emptyUsername_returnsNil() {
        XCTAssertNil(ILWebURL.profile(""))
    }

    func test_message_emptyId_returnsNil() {
        XCTAssertNil(ILWebURL.message(""))
    }

    // MARK: shared-token + public/authed resource links (SharingView)

    func test_sharedList_and_sharedDocument_buildTokenPaths() {
        XCTAssertEqual(ILWebURL.sharedList(token: "tok1")?.absoluteString,
                       "https://interlinedlist.com/lists/shared/tok1")
        XCTAssertEqual(ILWebURL.sharedDocument(token: "tok2")?.absoluteString,
                       "https://interlinedlist.com/documents/shared/tok2")
    }

    func test_publicResource_buildsOwnerScopedCanonicalPath() {
        XCTAssertEqual(ILWebURL.publicResource(kind: .documents, ownerUsername: "adron", id: "d1")?.absoluteString,
                       "https://interlinedlist.com/user/adron/documents/d1")
        XCTAssertEqual(ILWebURL.publicResource(kind: .lists, ownerUsername: "adron", id: "l1")?.absoluteString,
                       "https://interlinedlist.com/user/adron/lists/l1")
    }

    func test_publicResource_emptyOwner_returnsNil() {
        XCTAssertNil(ILWebURL.publicResource(kind: .lists, ownerUsername: "", id: "l1"))
    }

    func test_resource_buildsAuthedPermalink() {
        XCTAssertEqual(ILWebURL.resource(kind: .documents, id: "d1")?.absoluteString,
                       "https://interlinedlist.com/documents/d1")
        XCTAssertEqual(ILWebURL.resource(kind: .lists, id: "l1")?.absoluteString,
                       "https://interlinedlist.com/lists/l1")
    }
}
