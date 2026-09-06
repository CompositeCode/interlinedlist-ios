import XCTest
@testable import InterlinedList

final class AIArtifactTests: XCTestCase {

    private func encoded(_ artifact: AIArtifact) throws -> [String: Any] {
        let data = try JSONEncoder().encode(artifact)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decoded(_ json: String) throws -> AIArtifact {
        try JSONDecoder().decode(AIArtifact.self, from: Data(json.utf8))
    }

    func test_everyKindRoundTripsThroughItsDiscriminator() throws {
        let cases: [(String, AIArtifact)] = [
            (#"{"kind":"message","content":"hello"}"#, .message("hello")),
            (#"{"kind":"tags","tags":["a","b"]}"#, .tags(["a", "b"])),
            (#"{"kind":"thread","parts":["one","two"]}"#, .thread(["one", "two"])),
            (
                #"{"kind":"document","title":"T","markdown":"M","outline":["o"],"isPublic":true}"#,
                .document(AIDocumentArtifact(title: "T", markdown: "M", outline: ["o"], isPublic: true))
            ),
            (
                #"{"kind":"message_series","listTitle":"L","items":[{"order":1,"content":"c"}]}"#,
                .messageSeries(AIMessageSeriesArtifact(
                    listTitle: "L",
                    items: [AIMessageSeriesItem(order: 1, content: "c", scheduledAt: nil, crossPostTargets: nil)]
                ))
            ),
            (
                #"{"kind":"doc_series","folderTitle":"F","documents":[{"order":1,"title":"D"}]}"#,
                .docSeries(AIDocSeriesArtifact(
                    folderTitle: "F",
                    documents: [AIDocSeriesDocument(order: 1, title: "D", outline: nil, markdown: nil)]
                ))
            ),
            (
                #"{"kind":"list","title":"T","dsl":{"name":"T","fields":[]}}"#,
                .list(AIListArtifact(
                    title: "T",
                    description: nil,
                    dsl: .object(["name": .string("T"), "fields": .array([])]),
                    rows: nil
                ))
            ),
        ]
        for (json, expected) in cases {
            let artifact = try decoded(json)
            XCTAssertEqual(artifact, expected, "decoding \(json)")
            let reencoded = try encoded(artifact)
            XCTAssertEqual(reencoded["kind"] as? String, expected.kind)
        }
    }

    func test_encodingKeepsPayloadFieldsAlongsideKind() throws {
        let body = try encoded(.messageSeries(AIMessageSeriesArtifact(
            listTitle: "Launch",
            items: [AIMessageSeriesItem(order: 2, content: "second", scheduledAt: "2026-09-05T18:00", crossPostTargets: ["Bluesky"])]
        )))
        XCTAssertEqual(body["kind"] as? String, "message_series")
        XCTAssertEqual(body["listTitle"] as? String, "Launch")
        let items = try XCTUnwrap(body["items"] as? [[String: Any]])
        XCTAssertEqual(items[0]["order"] as? Int, 2)
        XCTAssertEqual(items[0]["scheduledAt"] as? String, "2026-09-05T18:00")
        XCTAssertEqual(items[0]["crossPostTargets"] as? [String], ["Bluesky"])
    }

    func test_unknownKindFailsToDecode() {
        XCTAssertThrowsError(try decoded(#"{"kind":"video","url":"x"}"#))
    }

    func test_listArtifactFieldLabelsFallBackToKey() throws {
        let artifact = try decoded(#"""
        {"kind":"list","title":"T","dsl":{"fields":[{"key":"a","label":"Alpha"},{"key":"b"}]}}
        """#)
        guard case .list(let list) = artifact else { return XCTFail("expected a list artifact") }
        XCTAssertEqual(list.fieldLabels, ["Alpha", "b"])
    }

    func test_listArtifactExposesColumnMetadataForThePreview() throws {
        let artifact = try decoded(#"""
        {"kind":"list","title":"Campaign","dsl":{"fields":[
          {"key":"message","label":"Message","type":"textarea","required":true},
          {"key":"channels","label":"Channels","type":"multiselect","options":["Bluesky","Mastodon"]},
          {"key":"scheduled_at","label":"Scheduled At","type":"datetime"}
        ]}}
        """#)
        guard case .list(let list) = artifact else { return XCTFail("expected a list artifact") }
        XCTAssertEqual(list.fields.map(\.id), ["message", "channels", "scheduled_at"])
        XCTAssertEqual(list.fields[0].type, "textarea")
        XCTAssertTrue(list.fields[0].isRequired)
        XCTAssertFalse(list.fields[1].isRequired)
        XCTAssertEqual(list.fields[1].options, ["Bluesky", "Mastodon"])
        XCTAssertTrue(list.fields[2].options.isEmpty)
    }

    func test_listArtifactRowSummaryPairsValuesWithLabelsInSchemaOrder() throws {
        let artifact = try decoded(#"""
        {"kind":"list","title":"Campaign",
         "dsl":{"fields":[{"key":"message","label":"Message","type":"text"},
                          {"key":"channels","label":"Channels","type":"multiselect"},
                          {"key":"notes","label":"Notes","type":"text"}]},
         "rows":[{"channels":["Bluesky","Mastodon"],"message":"Launch day","notes":null}]}
        """#)
        guard case .list(let list) = artifact, let row = list.rows?.first else {
            return XCTFail("expected a list artifact with a row")
        }
        let summary = list.rowSummary(row)
        XCTAssertEqual(summary.map(\.label), ["Message", "Channels"])
        XCTAssertEqual(summary.map(\.value), ["Launch day", "Bluesky, Mastodon"])
    }

    func test_listArtifactWithoutDslFieldsHasNoLabels() throws {
        let artifact = try decoded(#"{"kind":"list","title":"T","dsl":{"name":"T"}}"#)
        guard case .list(let list) = artifact else { return XCTFail("expected a list artifact") }
        XCTAssertTrue(list.fieldLabels.isEmpty)
    }

    // MARK: - AICreated

    func test_createdDecodesEachShape() throws {
        let list = try JSONDecoder().decode(AICreated.self, from: Data(#"{"listId":"l"}"#.utf8))
        XCTAssertEqual(list.listId, "l")
        XCTAssertNil(list.documentId)

        let doc = try JSONDecoder().decode(AICreated.self, from: Data(#"{"documentId":"d"}"#.utf8))
        XCTAssertEqual(doc.documentId, "d")

        let folder = try JSONDecoder().decode(AICreated.self, from: Data(#"{"folderId":"f","documentIds":["a"]}"#.utf8))
        XCTAssertEqual(folder.folderId, "f")
        XCTAssertEqual(folder.documentIds, ["a"])

        let scheduled = try JSONDecoder().decode(
            AICreated.self,
            from: Data(#"{"scheduledMessageIds":["m"],"firstScheduledAt":"t1","lastScheduledAt":"t2"}"#.utf8)
        )
        XCTAssertEqual(scheduled.scheduledMessageIds, ["m"])
        XCTAssertEqual(scheduled.lastScheduledAt, "t2")
    }

    // MARK: - Quota

    func test_quotaFallsBackToDifferenceWhenRemainingAbsent() throws {
        let quota = try JSONDecoder().decode(AIQuota.self, from: Data(#"{"usedToday":7,"dailyLimit":50}"#.utf8))
        XCTAssertEqual(quota.remaining, 43)
        XCTAssertFalse(quota.isExhausted)
    }

    func test_quotaPrefersReportedRemaining() throws {
        let quota = try JSONDecoder().decode(
            AIQuota.self,
            from: Data(#"{"usedToday":7,"dailyLimit":50,"remaining":0}"#.utf8)
        )
        XCTAssertEqual(quota.remaining, 0)
        XCTAssertTrue(quota.isExhausted)
    }

    func test_quotaNeverReportsNegativeRemaining() {
        XCTAssertEqual(AIQuota(usedToday: 60, dailyLimit: 50).remaining, 0)
    }
}
