//
//  ComposeImageUploaderTests.swift
//  InterlinedListTests
//

import XCTest
@testable import InterlinedList

private struct StubUploadError: Error {}

@MainActor
final class ComposeImageUploaderTests: XCTestCase {

    /// Echoes the uploaded bytes back as the URL, so ordering is easy to assert.
    private func echoUploader() -> ComposeImageUploader {
        ComposeImageUploader(uploadBytes: { data, _ in String(decoding: data, as: UTF8.self) })
    }

    private func upload(_ uploader: ComposeImageUploader, _ id: UUID, _ text: String) async {
        await uploader.performUpload(id: id, data: Data(text.utf8), mimeType: "image/jpeg")
    }

    func testReserveCapsAtEight() {
        let uploader = echoUploader()
        var reserved = 0
        for _ in 0..<12 where uploader.reserve() != nil { reserved += 1 }
        XCTAssertEqual(reserved, ComposeImageUploader.maxImages)
        XCTAssertEqual(uploader.count, 8)
        XCTAssertEqual(uploader.remainingSlots, 0)
    }

    func testUploadedURLsPreserveAttachmentOrder() async {
        let uploader = echoUploader()
        guard let a = uploader.reserve(), let b = uploader.reserve(), let c = uploader.reserve() else {
            return XCTFail("reserve failed")
        }
        // Complete out of order; result order should still follow attachment order.
        await upload(uploader, c, "C")
        await upload(uploader, a, "A")
        await upload(uploader, b, "B")
        XCTAssertEqual(uploader.uploadedURLs, ["A", "B", "C"])
        XCTAssertFalse(uploader.isUploading)
        XCTAssertFalse(uploader.hasFailures)
    }

    func testPartialFailureExcludesOnlyTheFailedImage() async {
        let uploader = ComposeImageUploader(uploadBytes: { data, _ in
            let text = String(decoding: data, as: UTF8.self)
            if text == "BAD" { throw StubUploadError() }
            return text
        })
        guard let a = uploader.reserve(), let bad = uploader.reserve(), let c = uploader.reserve() else {
            return XCTFail("reserve failed")
        }
        await upload(uploader, a, "A")
        await upload(uploader, bad, "BAD")
        await upload(uploader, c, "C")
        XCTAssertEqual(uploader.uploadedURLs, ["A", "C"])
        XCTAssertTrue(uploader.hasFailures)
    }

    func testRemoveDropsAttachmentAndFreesSlot() async {
        let uploader = echoUploader()
        guard let a = uploader.reserve(), let b = uploader.reserve() else {
            return XCTFail("reserve failed")
        }
        await upload(uploader, a, "A")
        await upload(uploader, b, "B")
        uploader.remove(a)
        XCTAssertEqual(uploader.uploadedURLs, ["B"])
        XCTAssertEqual(uploader.count, 1)
        XCTAssertEqual(uploader.remainingSlots, 7)
    }

    func testRetryOfFailedUploadSucceeds() async {
        actor Attempts { var n = 0; func next() -> Int { n += 1; return n } }
        let attempts = Attempts()
        let uploader = ComposeImageUploader(uploadBytes: { _, _ in
            let n = await attempts.next()
            if n == 1 { throw StubUploadError() }
            return "ok"
        })
        guard let a = uploader.reserve() else { return XCTFail("reserve failed") }
        await upload(uploader, a, "x")
        XCTAssertTrue(uploader.hasFailures)
        XCTAssertTrue(uploader.uploadedURLs.isEmpty)

        // performUpload is the same path retry() runs after re-loading the source.
        await upload(uploader, a, "x")
        XCTAssertEqual(uploader.uploadedURLs, ["ok"])
        XCTAssertFalse(uploader.hasFailures)
    }

    func testResetClearsEverything() async {
        let uploader = echoUploader()
        guard let a = uploader.reserve() else { return XCTFail("reserve failed") }
        await upload(uploader, a, "A")
        uploader.reset()
        XCTAssertTrue(uploader.attachments.isEmpty)
        XCTAssertTrue(uploader.uploadedURLs.isEmpty)
        XCTAssertEqual(uploader.remainingSlots, ComposeImageUploader.maxImages)
    }

    func testMoveAttachmentReordersUploadedURLs() async {
        let uploader = echoUploader()
        guard let a = uploader.reserve(), let b = uploader.reserve(), let c = uploader.reserve() else {
            return XCTFail("reserve failed")
        }
        await upload(uploader, a, "A")
        await upload(uploader, b, "B")
        await upload(uploader, c, "C")
        XCTAssertEqual(uploader.uploadedURLs, ["A", "B", "C"])

        // Drag C ahead of A -> C, A, B
        uploader.moveAttachment(c, ahead: a)
        XCTAssertEqual(uploader.uploadedURLs, ["C", "A", "B"])

        // Drag A (now at index 1) ahead of B (index 2) -> C, B, A
        uploader.moveAttachment(a, ahead: b)
        XCTAssertEqual(uploader.uploadedURLs, ["C", "B", "A"])
    }

    func testMoveAttachmentOntoItselfIsNoOp() async {
        let uploader = echoUploader()
        guard let a = uploader.reserve(), let b = uploader.reserve() else {
            return XCTFail("reserve failed")
        }
        await upload(uploader, a, "A")
        await upload(uploader, b, "B")
        uploader.moveAttachment(a, ahead: a)
        XCTAssertEqual(uploader.uploadedURLs, ["A", "B"])
    }

    func testIsUploadingWhileSlotReservedButNotYetComplete() {
        let uploader = echoUploader()
        _ = uploader.reserve()
        XCTAssertTrue(uploader.isUploading)
        XCTAssertTrue(uploader.uploadedURLs.isEmpty)
    }
}
