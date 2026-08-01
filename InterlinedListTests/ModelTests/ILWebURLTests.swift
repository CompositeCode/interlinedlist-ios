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
}
