import XCTest
@testable import InterlinedList

/// The client-side gates and derivations that decide what the composer sends —
/// each one mirrors a server rule, so a drift here shows up as a wasted quota
/// unit or a mis-sized series.
final class AIComposerLogicTests: XCTestCase {

    // MARK: - Word gate (COMPOSER_MIN_WORDS)

    func test_countWordsIgnoresExtraWhitespaceAndNewlines() {
        XCTAssertEqual(AILimits.countWords(""), 0)
        XCTAssertEqual(AILimits.countWords("   "), 0)
        XCTAssertEqual(AILimits.countWords("one"), 1)
        XCTAssertEqual(AILimits.countWords("one   two\n\nthree"), 3)
    }

    func test_seriesMinimumMatchesServerThreshold() {
        XCTAssertEqual(AILimits.composerMinWords, 10)
        let nineWords = "one two three four five six seven eight nine"
        let tenWords = nineWords + " ten"
        XCTAssertFalse(AILimits.meetsSeriesMinimum(nineWords))
        XCTAssertTrue(AILimits.meetsSeriesMinimum(tenWords))
    }

    func test_perFeatureInputWordCeilingsMatchTheServer() {
        XCTAssertEqual(AILimits.maxInputWords(.writingAssist), 1500)
        XCTAssertEqual(AILimits.maxInputWords(.poweredTemplate), 300)
        XCTAssertEqual(AILimits.maxInputWords(.messageSeries), 500)
        XCTAssertEqual(AILimits.maxInputWords(.poweredDocument), 500)
        XCTAssertEqual(AILimits.maxInputWords(.articleSeries), 500)
    }

    // MARK: - Cross-post selection → channel labels

    func test_channelLabelsMirrorTheServerMapping() {
        let selection = AIComposerCrossPost(
            crossPostToBluesky: true,
            selectedMastodonIds: ["m1"],
            crossPostToTwitter: true,
            crossPostToLinkedIn: true
        )
        XCTAssertEqual(selection.channelLabels, ["Bluesky", "Mastodon", "LinkedIn", "X/Twitter"])
    }

    func test_channelLabelsIgnoreEmptyMastodonSelection() {
        let selection = AIComposerCrossPost(crossPostToBluesky: true, selectedMastodonIds: [])
        XCTAssertEqual(selection.channelLabels, ["Bluesky"])
    }

    func test_emptySelectionHasNoLabels() {
        XCTAssertTrue(AIComposerCrossPost().channelLabels.isEmpty)
        XCTAssertTrue(AIComposerCrossPost().isEmpty)
        XCTAssertFalse(AIComposerCrossPost(crossPostToTwitter: true).isEmpty)
    }

    // MARK: - Series sizing

    func test_charLimitIsTheTightestSelectedService() {
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: ["Bluesky", "LinkedIn"], fallback: 666), 300)
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: ["LinkedIn"], fallback: 666), 3000)
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: ["X/Twitter", "Mastodon"], fallback: 666), 280)
    }

    func test_charLimitFallsBackWhenNothingMapsToAChannel() {
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: [], fallback: 666), 666)
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: ["Blog", "Newsletter"], fallback: 666), 666)
    }

    func test_charLimitAcceptsTheAliasesTheServerAccepts() {
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: ["twitter"], fallback: 666), 280)
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: [" X "], fallback: 666), 280)
        XCTAssertEqual(AICrossPostLimits.minCharLimit(labels: ["bluesky"], fallback: 666), 300)
    }

    // MARK: - Loading captions

    func test_loadingStepAdvancesThenClamps() {
        let captions = AISeriesLoading.captions(for: .messageSeries)
        XCTAssertEqual(AISeriesLoading.stepIndex(elapsed: 0, captionCount: captions.count), 0)
        XCTAssertEqual(AISeriesLoading.stepIndex(elapsed: 2.6, captionCount: captions.count), 1)
        XCTAssertEqual(AISeriesLoading.stepIndex(elapsed: 7.6, captionCount: captions.count), 3)
        XCTAssertEqual(AISeriesLoading.stepIndex(elapsed: 600, captionCount: captions.count), captions.count - 1)
    }

    func test_loadingStepHandlesDegenerateInput() {
        XCTAssertEqual(AISeriesLoading.stepIndex(elapsed: -5, captionCount: 4), 0)
        XCTAssertEqual(AISeriesLoading.stepIndex(elapsed: 10, captionCount: 0), 0)
    }

    func test_loadingCopyIsFeatureSpecific() {
        XCTAssertTrue(AISeriesLoading.title(for: .messageSeries).contains("message series"))
        XCTAssertTrue(AISeriesLoading.title(for: .articleSeries).contains("article series"))
        XCTAssertNotEqual(
            AISeriesLoading.captions(for: .messageSeries),
            AISeriesLoading.captions(for: .articleSeries)
        )
    }

    // MARK: - Post-generate confirmation copy

    func test_confirmationForScheduledMessages() {
        let created = AICreated(
            scheduledMessageIds: ["a", "b", "c"],
            firstScheduledAt: "2026-09-05T18:00:00.000Z"
        )
        let copy = AISeriesSheet.confirmation(for: created)
        XCTAssertTrue(copy.hasPrefix("Scheduled 3 messages — first around "), copy)
    }

    func test_confirmationSingularizesOneMessage() {
        let created = AICreated(scheduledMessageIds: ["a"])
        XCTAssertEqual(AISeriesSheet.confirmation(for: created), "Scheduled 1 message.")
    }

    func test_confirmationForListAndFolder() {
        XCTAssertEqual(
            AISeriesSheet.confirmation(for: AICreated(listId: "l1")),
            "Message series list created."
        )
        XCTAssertEqual(
            AISeriesSheet.confirmation(for: AICreated(folderId: "f1", documentIds: ["a", "b"])),
            "Article series created (2 documents)."
        )
    }

    func test_confirmationFallsBackWhenServerReportsNothingKnown() {
        XCTAssertEqual(AISeriesSheet.confirmation(for: AICreated()), "Created.")
    }

    // MARK: - Context builders

    func test_contextBuildersSetOnlyTheirOwnFields() {
        let assist = AIContext.writingAssist(.grammar)
        XCTAssertEqual(assist.action, "grammar")
        XCTAssertNil(assist.mode)

        let template = AIContext.poweredTemplate(templateKey: "article_series")
        XCTAssertEqual(template.templateKey, "article_series")
        XCTAssertNil(template.action)

        let series = AIContext.messageSeries(channels: ["Bluesky"])
        XCTAssertEqual(series.channels, ["Bluesky"])

        let document = AIContext.poweredDocument(mode: .fromList, listId: "l1")
        XCTAssertEqual(document.mode, "from_list")
        XCTAssertEqual(document.listId, "l1")
        XCTAssertNil(document.documentId)
        XCTAssertNil(document.url)
    }
}
