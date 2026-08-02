//
//  NetworkReachability.swift
//  InterlinedList
//

import Foundation
import Network

/// Lightweight connectivity signal over `NWPathMonitor`. Fires `onReconnect` when
/// connectivity transitions from unsatisfied → satisfied, so the caller can replay
/// a queued outbox. The callback is delivered on the main actor.
@MainActor
final class NetworkReachability {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.interlinedlist.reachability")
    private var lastSatisfied: Bool?
    private var onReconnect: (() -> Void)?

    private(set) var isConnected = true

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
    }

    /// Starts monitoring. `onReconnect` fires on each unsatisfied → satisfied edge
    /// (not on the initial reading, which just seeds the baseline).
    func start(onReconnect: @escaping () -> Void) {
        self.onReconnect = onReconnect
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handle(satisfied: satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        onReconnect = nil
    }

    private func handle(satisfied: Bool) {
        isConnected = satisfied
        defer { lastSatisfied = satisfied }
        guard let previous = lastSatisfied else { return }
        if satisfied && !previous {
            onReconnect?()
        }
    }
}
