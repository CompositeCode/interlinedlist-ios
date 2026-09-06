//
//  AIService.swift
//  InterlinedList
//

import Foundation
import os.log

private let aiServiceLog = Logger(subsystem: "com.interlinedlist.app", category: "AIService")

/// Owns AI availability and the shared daily quota for every AI affordance.
///
/// AI is included with the subscription and runs on the app's own server-side
/// provider key, so availability is **one flag**: `subscriber`. There is no key
/// entry, no provider picker, and no BYO-key state to model. A free user sees no
/// AI control at all — never a disabled one, and never price or upgrade copy
/// (App Store Guideline 3.1.1).
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    @Published private(set) var status: AIStatus?
    /// Both `/suggest` and `/generate` decrement the same 50/day counter, so this
    /// tracks whichever response spoke most recently.
    @Published private(set) var quota: AIQuota?
    /// Set when the server says it cannot serve AI at all right now
    /// (`no_provider_configured`, i.e. a misconfigured or down provider) or the
    /// entitlement is missing. Hides every affordance for the rest of the session.
    @Published private(set) var isDisabledForSession = false

    private let api: APIClient
    /// Several AI surfaces ask for the status as they appear; they share one
    /// request rather than each firing their own.
    private var statusLoad: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// The single visibility gate. The locally-known `customerStatus` decides on
    /// first render — it is the same value the server computes into
    /// `status.subscriber` — and a loaded `/status` supersedes it.
    func isAvailable(for user: User?) -> Bool {
        if isDisabledForSession { return false }
        if let status { return status.subscriber }
        return user?.isSubscriber == true
    }

    /// Attribution for a sheet footer. Display metadata, never a precondition.
    var attribution: String? { status?.attribution }

    func loadStatusIfNeeded() async {
        guard status == nil, !isDisabledForSession else { return }
        await refreshStatus()
    }

    func refreshStatus() async {
        if let existing = statusLoad {
            await existing.value
            return
        }
        let load = Task { await performStatusRefresh() }
        statusLoad = load
        await load.value
        statusLoad = nil
    }

    private func performStatusRefresh() async {
        do {
            let fetched = try await api.aiStatus()
            status = fetched
            quota = fetched.quota
        } catch let error as AIServiceError {
            // A failed status read must not hide a control the user is entitled
            // to; only an explicit "cannot serve AI" does that.
            if case .unavailable = error { isDisabledForSession = true }
            aiServiceLog.error("aiStatus failed: \(error.userMessage)")
        } catch {
            aiServiceLog.error("aiStatus failed: \(error.localizedDescription)")
        }
    }

    /// Preview an artifact without writing anything. Bills one quota unit.
    func suggest(
        feature: AIFeature,
        input: String,
        context: AIContext? = nil
    ) async throws -> AIArtifact {
        do {
            let suggestion = try await api.aiSuggest(feature: feature, input: input, context: context)
            if let updated = suggestion.quota { quota = updated }
            return suggestion.artifact
        } catch let error as AIServiceError {
            record(error)
            throw error
        }
    }

    /// Persist a confirmed artifact. Bills a second quota unit.
    func generate(
        feature: AIFeature,
        artifact: AIArtifact,
        channels: [String]? = nil,
        scheduleImmediately: Bool? = nil,
        crossPost: AIComposerCrossPost? = nil
    ) async throws -> AICreated {
        do {
            let result = try await api.aiGenerate(
                feature: feature,
                artifact: artifact,
                channels: channels,
                scheduleImmediately: scheduleImmediately,
                crossPost: crossPost
            )
            if let updated = result.quota { quota = updated }
            return result.created
        } catch let error as AIServiceError {
            record(error)
            throw error
        }
    }

    /// Folds a failure back into the shared state: an entitlement or outage
    /// failure retires the affordance, and a quota rejection zeroes the counter
    /// so the remaining-count copy stops promising runs that will be refused.
    private func record(_ error: AIServiceError) {
        if error.hidesAffordance { isDisabledForSession = true }
        if case .quotaExceeded = error, let current = quota {
            quota = AIQuota(usedToday: current.dailyLimit, dailyLimit: current.dailyLimit, remaining: 0)
        }
    }
}
