//
//  ComposeImageUploader.swift
//  InterlinedList
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// Coordinates attaching up to `maxImages` images to a compose draft: reserves
/// ordered slots (capped), normalizes + uploads each picked image, and tracks
/// per-image status so the UI can show progress, retry failures, and post the
/// images that succeeded. HTTP stays in `APIClient`; this owns only compose state.
@MainActor
final class ComposeImageUploader: ObservableObject {
    nonisolated static let maxImages = 8

    struct Attachment: Identifiable {
        let id: UUID
        var preview: UIImage?
        var status: Status

        enum Status: Equatable {
            case uploading
            case uploaded(String)
            case failed
        }
    }

    @Published private(set) var attachments: [Attachment] = []

    /// Retained per attachment so a failed upload can be retried from its source.
    private var sources: [UUID: PhotosPickerItem] = [:]

    /// Injected so tests exercise the state machine without a live network.
    private let uploadBytes: (Data, String) async throws -> String

    init(uploadBytes: @escaping (Data, String) async throws -> String = { data, mime in
        try await APIClient.shared.uploadImage(data: data, mimeType: mime)
    }) {
        self.uploadBytes = uploadBytes
    }

    // MARK: - Derived state

    var count: Int { attachments.count }
    var isEmpty: Bool { attachments.isEmpty }
    var remainingSlots: Int { max(0, Self.maxImages - attachments.count) }
    var isUploading: Bool { attachments.contains { $0.status == .uploading } }
    var hasFailures: Bool { attachments.contains { $0.status == .failed } }

    /// Successfully-uploaded URLs, in attachment (display) order.
    var uploadedURLs: [String] {
        attachments.compactMap {
            if case .uploaded(let url) = $0.status { return url }
            return nil
        }
    }

    // MARK: - State machine (unit-tested)

    /// Reserve an ordered slot if under the cap. Returns its id, or nil when full.
    @discardableResult
    func reserve(preview: UIImage? = nil) -> UUID? {
        guard attachments.count < Self.maxImages else { return nil }
        let id = UUID()
        attachments.append(Attachment(id: id, preview: preview, status: .uploading))
        return id
    }

    /// Upload already-loaded bytes and record the outcome for `id`.
    func performUpload(id: UUID, data: Data, mimeType: String) async {
        setStatus(.uploading, for: id)
        do {
            let url = try await uploadBytes(data, mimeType)
            setStatus(.uploaded(url), for: id)
        } catch {
            setStatus(.failed, for: id)
        }
    }

    func remove(_ id: UUID) {
        attachments.removeAll { $0.id == id }
        sources[id] = nil
    }

    func reset() {
        attachments.removeAll()
        sources.removeAll()
    }

    // MARK: - PhotosPicker integration

    /// Ingest newly-picked items: reserve slots (respecting the cap), then load,
    /// normalize, and upload each with bounded concurrency.
    func add(_ items: [PhotosPickerItem]) async {
        var reserved: [(id: UUID, item: PhotosPickerItem)] = []
        for item in items {
            guard let id = reserve() else { break } // cap reached
            sources[id] = item
            reserved.append((id, item))
        }
        await withTaskGroup(of: Void.self) { group in
            let maxConcurrent = 3
            var running = 0
            for entry in reserved {
                if running >= maxConcurrent {
                    await group.next()
                    running -= 1
                }
                group.addTask { await self.loadNormalizeUpload(id: entry.id, item: entry.item) }
                running += 1
            }
            while await group.next() != nil {}
        }
    }

    /// Retry a failed attachment from its original picked source.
    func retry(_ id: UUID) async {
        guard let item = sources[id] else {
            setStatus(.failed, for: id)
            return
        }
        await loadNormalizeUpload(id: id, item: item)
    }

    private func loadNormalizeUpload(id: UUID, item: PhotosPickerItem) async {
        setStatus(.uploading, for: id)
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            setStatus(.failed, for: id)
            return
        }
        let processed = await Task.detached(priority: .userInitiated) {
            ImageUploadProcessor.process(raw)
        }.value
        let data = processed?.data ?? raw
        let mimeType = processed?.mimeType ?? (item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg")
        setPreview(UIImage(data: data), for: id)
        await performUpload(id: id, data: data, mimeType: mimeType)
    }

    // MARK: - Private helpers

    private func index(of id: UUID) -> Int? { attachments.firstIndex { $0.id == id } }

    private func setStatus(_ status: Attachment.Status, for id: UUID) {
        guard let i = index(of: id) else { return }
        attachments[i].status = status
    }

    private func setPreview(_ image: UIImage?, for id: UUID) {
        guard let i = index(of: id) else { return }
        attachments[i].preview = image
    }

    #if DEBUG
    /// Seed an uploader with fixed statuses for SwiftUI previews.
    static func previewSeed(_ statuses: [Attachment.Status]) -> ComposeImageUploader {
        let uploader = ComposeImageUploader(uploadBytes: { _, _ in "" })
        uploader.attachments = statuses.map { Attachment(id: UUID(), preview: nil, status: $0) }
        return uploader
    }
    #endif
}
