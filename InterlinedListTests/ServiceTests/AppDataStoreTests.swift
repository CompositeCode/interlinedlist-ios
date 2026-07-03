import XCTest
@testable import InterlinedList

@MainActor
final class AppDataStoreTests: XCTestCase {
    var sut: AppDataStore!

    override func setUp() {
        super.setUp()
        sut = AppDataStore()
    }

    // MARK: - insertFeedMessage

    func test_insertFeedMessage_insertsAtHead() {
        let first = makeMessage(id: "a")
        let second = makeMessage(id: "b")
        sut.insertFeedMessage(first)
        sut.insertFeedMessage(second)
        // Most recently inserted should be at index 0.
        XCTAssertEqual(sut.feedMessages.first?.id, "b")
        XCTAssertEqual(sut.feedMessages.last?.id, "a")
    }

    func test_insertFeedMessage_incrementsCount() {
        XCTAssertEqual(sut.feedMessages.count, 0)
        sut.insertFeedMessage(makeMessage(id: "x"))
        XCTAssertEqual(sut.feedMessages.count, 1)
        sut.insertFeedMessage(makeMessage(id: "y"))
        XCTAssertEqual(sut.feedMessages.count, 2)
    }

    func test_insertFeedMessage_preservesExistingMessages() {
        sut.insertFeedMessage(makeMessage(id: "old"))
        sut.insertFeedMessage(makeMessage(id: "new"))
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "old" })
        XCTAssertTrue(sut.feedMessages.contains { $0.id == "new" })
    }

    // MARK: - reset

    func test_reset_clearsFeedMessages() {
        sut.insertFeedMessage(makeMessage(id: "x"))
        sut.reset()
        XCTAssertTrue(sut.feedMessages.isEmpty)
    }

    func test_reset_resetsLoadingFlag() {
        // feedLoading starts true, goes false after a refresh; reset should restore true.
        sut.reset()
        XCTAssertTrue(sut.feedLoading)
    }

    // MARK: - optimistic document mutations

    func test_insertDocument_insertsAtHead() {
        let doc = makeDocument(id: "d1")
        sut.insertDocument(doc)
        XCTAssertEqual(sut.documents.first?.id, "d1")
    }

    func test_removeDocument_removesById() {
        sut.insertDocument(makeDocument(id: "d1"))
        sut.insertDocument(makeDocument(id: "d2"))
        sut.removeDocument(id: "d1")
        XCTAssertFalse(sut.documents.contains { $0.id == "d1" })
        XCTAssertTrue(sut.documents.contains { $0.id == "d2" })
    }

    // MARK: - Helpers

    private func makeMessage(id: String) -> Message {
        Message(id: id, content: "test", publiclyVisible: true,
                userId: "u1", createdAt: "2026-01-01T00:00:00Z",
                updatedAt: nil, user: nil, imageUrls: nil, videoUrls: nil,
                linkMetadata: nil, parentId: nil, scheduledAt: nil,
                tags: nil, digCount: 0, dugByMe: false, crossPostUrls: nil)
    }

    private func makeDocument(id: String) -> Document {
        Document(id: id, title: "Doc \(id)", content: nil,
                 folderId: nil, isPublic: false,
                 createdAt: "2026-01-01T00:00:00Z", updatedAt: nil)
    }
}
