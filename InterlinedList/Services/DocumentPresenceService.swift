//
//  DocumentPresenceService.swift
//  InterlinedList
//

import Foundation

/// Drives the presence heartbeat for one open document.
///
/// A phone must not poll from the background, so the heartbeat runs only while a
/// document is on screen **and** the scene is active; `stop()` cancels the loop and
/// sends an explicit leave. There is no SSE/WebSocket anywhere in the product —
/// polling is the intended pattern (`components/documents/usePresence.ts`).
@MainActor
final class DocumentPresenceService: ObservableObject {
    /// Other editors currently in the document. Never includes this account.
    @Published private(set) var others: [DocumentPresenceUser] = []
    /// True once the server reports a version newer than the one this editor opened,
    /// i.e. a peer has saved. A signal for the existing refresh/merge path — this
    /// service never mutates document content itself.
    @Published private(set) var isStale = false

    /// The web beats every 1.5s against an 8s active window. Matching it keeps a
    /// peer's arrival visible within one heartbeat while staying well inside the
    /// window, so a single dropped request never makes a viewer flicker away.
    private let interval: Duration
    private let api: APIClient
    private var task: Task<Void, Never>?
    private var documentId: String?
    private var baseVersion: Int?

    init(api: APIClient = .shared, interval: Duration = .milliseconds(1500)) {
        self.api = api
        self.interval = interval
    }

    var viewerCount: Int { others.count }

    /// The baseline is the version reported by the *first* heartbeat, because
    /// `GET /api/documents/:id` does not carry a version for the client to open
    /// against. Anything above it means a peer saved while this editor was open —
    /// which is exactly the condition worth surfacing.
    func start(documentId: String) {
        guard task == nil else { return }
        self.documentId = documentId
        self.baseVersion = nil
        isStale = false
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.beat()
                guard let interval = self?.interval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        others = []
        isStale = false
        guard let documentId else { return }
        self.documentId = nil
        // Fire-and-forget: the server's active window expires this row anyway, so a
        // failed leave costs at most a few seconds of a stale viewer for peers.
        Task { [api] in try? await api.leaveDocumentPresence(id: documentId) }
    }

    private func beat() async {
        guard let documentId else { return }
        do {
            let response = try await api.documentPresence(id: documentId)
            others = response.users
            if let version = response.version {
                if let baseVersion {
                    if version > baseVersion { isStale = true }
                } else {
                    baseVersion = version
                }
            }
        } catch {
            // Presence is advisory. A failed beat must not surface an error or stop
            // the loop — the next one may well succeed.
        }
    }

    deinit {
        task?.cancel()
    }
}
