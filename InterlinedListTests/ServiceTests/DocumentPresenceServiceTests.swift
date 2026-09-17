import XCTest
@testable import InterlinedList

@MainActor
final class DocumentPresenceServiceTests: XCTestCase {
    var session: MockURLSession!
    var api: APIClient!
    var sut: DocumentPresenceService!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        api = APIClient(session: session)
        api.setBearerToken("tok")
        // A short interval keeps the lifecycle tests fast without changing behaviour.
        sut = DocumentPresenceService(api: api, interval: .milliseconds(20))
    }

    override func tearDown() {
        sut.stop()
        super.tearDown()
    }

    private func stubPresence(users: String = "[]", version: String = "null") {
        session.stub(json: #"{"users":\#(users),"version":\#(version)}"#)
    }

    private func waitForBeat() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    func test_startPublishesOtherEditors() async {
        stubPresence(users: #"[{"userId":"u2","name":"Bob","color":null,"anchor":null,"head":null}]"#)
        sut.start(documentId: "d1")
        await waitForBeat()
        XCTAssertEqual(sut.viewerCount, 1)
        XCTAssertEqual(sut.others.first?.name, "Bob")
    }

    func test_stopClearsViewersAndSendsLeave() async {
        stubPresence(users: #"[{"userId":"u2","name":"Bob","color":null,"anchor":null,"head":null}]"#)
        sut.start(documentId: "d1")
        await waitForBeat()
        XCTAssertEqual(sut.viewerCount, 1)

        session.stub(json: #"{"ok":true}"#)
        sut.stop()
        XCTAssertEqual(sut.viewerCount, 0, "Viewers must clear immediately, not on the next beat")
        await waitForBeat()
        XCTAssertEqual(session.lastRequest?.httpMethod, "DELETE", "stop() must send an explicit leave")
    }

    func test_stopHaltsPolling() async {
        stubPresence()
        sut.start(documentId: "d1")
        await waitForBeat()
        session.stub(json: #"{"ok":true}"#)
        sut.stop()
        await waitForBeat()
        let countAfterStop = session.requestHistory.count
        await waitForBeat()
        XCTAssertEqual(
            session.requestHistory.count, countAfterStop,
            "No request may be issued once the editor is off screen or the app is backgrounded"
        )
    }

    func test_startIsIdempotent() async {
        stubPresence()
        sut.start(documentId: "d1")
        sut.start(documentId: "d1")
        await waitForBeat()
        // Two overlapping loops would roughly double the request count.
        XCTAssertLessThanOrEqual(session.requestHistory.count, 8)
    }

    func test_versionAboveTheFirstObservedMarksStale() async {
        stubPresence(version: "4")
        sut.start(documentId: "d1")
        await waitForBeat()
        XCTAssertFalse(sut.isStale, "The first version seen is the baseline, not a change")

        stubPresence(version: "5")
        await waitForBeat()
        XCTAssertTrue(sut.isStale, "A peer saving must raise the staleness signal")
    }

    func test_aFailedBeatIsSwallowedAndPollingContinues() async {
        session.stub(data: Data(), statusCode: 500)
        sut.start(documentId: "d1")
        await waitForBeat()
        XCTAssertEqual(sut.viewerCount, 0)

        stubPresence(users: #"[{"userId":"u2","name":"Bob","color":null,"anchor":null,"head":null}]"#)
        await waitForBeat()
        XCTAssertEqual(sut.viewerCount, 1, "The loop must survive a failed heartbeat")
    }
}
