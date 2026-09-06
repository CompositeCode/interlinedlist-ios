//
//  ServerLimitsStore.swift
//  InterlinedList
//

import Foundation

/// Holds the server's upload caps for the lifetime of the app, refreshed once at
/// launch.
///
/// Not an `ObservableObject`: its only consumer is `ImageUploadProcessor`, which
/// runs on a detached task off the main actor, so this has to be readable from
/// any thread rather than isolated to one. An `NSLock` around a single value is
/// the whole implementation.
final class ServerLimitsStore: @unchecked Sendable {
    static let shared = ServerLimitsStore()

    private let lock = NSLock()
    private var storedLimits: ServerLimits = .fallback
    private let fetch: @Sendable () async throws -> ServerLimits

    init(fetch: @escaping @Sendable () async throws -> ServerLimits = { try await APIClient.shared.serverLimits() }) {
        self.fetch = fetch
    }

    var limits: ServerLimits {
        lock.withLock { storedLimits }
    }

    var imageLimits: ImageUploadLimits {
        ImageUploadLimits(limits)
    }

    /// Best-effort: on failure the fallback caps stay in place, which match what
    /// the backend enforces today, so an upload is never blocked by this.
    func refresh() async {
        guard let fetched = try? await fetch() else { return }
        lock.withLock { storedLimits = fetched }
    }
}
