//
//  AISeriesSheet.swift
//  InterlinedList
//

import SwiftUI
import Combine

/// Message Series / Article Series: the full suggest → preview → confirm →
/// generate flow. Both steps bill against the shared 50/day AI quota, so the
/// preview is a real decision point, not a formality.
struct AISeriesSheet: View {
    let feature: AIFeature
    /// The composer draft the series is generated from.
    let input: String
    /// The composer's live cross-post selection. Message Series reads it rather
    /// than offering a second picker: it sizes the generated posts, and — when
    /// scheduling directly — decides which accounts they cross-post to.
    let crossPost: AIComposerCrossPost
    /// The user's own message limit, used when nothing is cross-posted.
    let fallbackCharLimit: Int
    let onCreated: (AICreated) -> Void

    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var ai = AIService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var artifact: AIArtifact?
    @State private var created: AICreated?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var canRetry = false
    @State private var scheduleImmediately = false
    @State private var elapsed: TimeInterval = 0

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var channelLabels: [String] { crossPost.channelLabels }

    private var charLimit: Int {
        AICrossPostLimits.minCharLimit(labels: channelLabels, fallback: fallbackCharLimit)
    }

    private var isMessageSeries: Bool { feature == .messageSeries }

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    createdSection(created)
                } else if let artifact {
                    previewSections(artifact)
                } else {
                    loadingSection
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "Cancel" : "Done") { dismiss() }
                }
                if artifact != nil && created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmLabel) { Task { await confirm() } }
                            .disabled(isWorking)
                    }
                }
            }
            .task { await generatePreview() }
            .onReceive(ticker) { _ in
                guard artifact == nil, created == nil, errorMessage == nil else { return }
                elapsed += 0.5
            }
        }
    }

    private var navTitle: String {
        isMessageSeries ? "Message Series" : "Article Series"
    }

    private var confirmLabel: String {
        (isMessageSeries && scheduleImmediately) ? "Schedule" : "Create"
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(.ilBody(15))
                    .foregroundStyle(.red)
                if canRetry {
                    Button("Try Again") {
                        Task { await generatePreview(isRetry: true) }
                    }
                    .disabled(isWorking)
                }
            }
        } else {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentCaption)
                            .font(.ilBody(15))
                        Text("\(Int(elapsed))s elapsed")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(currentCaption). \(Int(elapsed)) seconds elapsed.")
            } header: {
                Text(AISeriesLoading.title(for: feature))
            }
        }
    }

    private var currentCaption: String {
        let captions = AISeriesLoading.captions(for: feature)
        let index = AISeriesLoading.stepIndex(elapsed: elapsed, captionCount: captions.count)
        return captions[index]
    }

    // MARK: - Preview

    @ViewBuilder
    private func previewSections(_ artifact: AIArtifact) -> some View {
        switch artifact {
        case .messageSeries(let series):
            Section {
                ForEach(Array(series.items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1)")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                        Text(item.content)
                            .font(.ilBody(15))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Message \(index + 1): \(item.content)")
                }
            } header: {
                Text(series.listTitle)
            } footer: {
                Text(sizingNote)
                    .font(.ilMono())
            }
            Section {
                Toggle("Schedule immediately", isOn: $scheduleImmediately)
                    .accessibilityLabel("Schedule these messages immediately instead of creating a list")
            } footer: {
                Text(scheduleImmediately
                     ? "Posts directly — the first in about 30–45 minutes, then 5–10 minutes apart."
                     : "Creates a list you can review and schedule yourself.")
                    .font(.ilMono())
            }
        case .docSeries(let series):
            Section {
                ForEach(Array(series.documents.enumerated()), id: \.offset) { index, document in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.ilBody(15))
                            .fontWeight(.medium)
                        if let outline = document.outline, !outline.isEmpty {
                            Text(outline.joined(separator: " · "))
                                .font(.ilMono())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Document \(index + 1): \(document.title)")
                }
            } header: {
                Text(series.folderTitle)
            } footer: {
                Text("Creates a folder of \(series.documents.count) documents you can edit.")
                    .font(.ilMono())
            }
        default:
            Section {
                Text("That result can't be used as a series.")
                    .font(.ilBody(15))
                    .foregroundStyle(.secondary)
            }
        }
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(.ilBody(15))
                    .foregroundStyle(.red)
            }
        }
        quotaFooterSection
    }

    private var sizingNote: String {
        if channelLabels.isEmpty {
            return "In-app only — no cross-post selected. Sized to fit \(charLimit) characters."
        }
        return "Cross-posts to \(channelLabels.joined(separator: ", ")) — sized to fit \(charLimit) characters."
    }

    @ViewBuilder
    private var quotaFooterSection: some View {
        if let quota = ai.quota {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(quota.remaining) of \(quota.dailyLimit) AI runs left today. Creating uses one more.")
                    if let attribution = ai.attribution {
                        Text(attribution)
                    }
                }
                .font(.ilMono())
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Created

    @ViewBuilder
    private func createdSection(_ created: AICreated) -> some View {
        Section {
            Label(Self.confirmation(for: created), systemImage: "checkmark.circle.fill")
                .font(.ilBody(15))
                .foregroundStyle(Color(ILColor.primary))
        } footer: {
            if created.scheduledMessageIds != nil {
                Text("Review or edit them under Scheduled.")
                    .font(.ilMono())
            }
        }
    }

    /// Mirrors the web's post-generate confirmation copy.
    static func confirmation(for created: AICreated) -> String {
        if let ids = created.scheduledMessageIds {
            let noun = ids.count == 1 ? "message" : "messages"
            guard let first = created.firstScheduledAt, let date = parseTimestamp(first) else {
                return "Scheduled \(ids.count) \(noun)."
            }
            let time = date.formatted(date: .omitted, time: .shortened)
            return "Scheduled \(ids.count) \(noun) — first around \(time)."
        }
        if created.listId != nil {
            return "Message series list created."
        }
        if created.folderId != nil {
            let count = created.documentIds?.count ?? 0
            return "Article series created (\(count) documents)."
        }
        return "Created."
    }

    private static func parseTimestamp(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    // MARK: - Actions

    private func generatePreview(isRetry: Bool = false) async {
        guard artifact == nil, !isWorking else { return }
        errorMessage = nil
        canRetry = false
        if isRetry { elapsed = 0 }
        isWorking = true
        defer { isWorking = false }
        do {
            artifact = try await ai.suggest(
                feature: feature,
                input: input,
                context: isMessageSeries ? .messageSeries(channels: channelLabels) : nil
            )
        } catch AIServiceError.unauthorized {
            authState.handleUnauthorized()
            dismiss()
        } catch let error as AIServiceError {
            errorMessage = error.userMessage
            canRetry = error.isRetryable
        } catch {
            errorMessage = AIServiceError.transport.userMessage
            canRetry = true
        }
    }

    private func confirm() async {
        guard let artifact, !isWorking else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await ai.generate(
                feature: feature,
                artifact: artifact,
                channels: isMessageSeries ? channelLabels : nil,
                scheduleImmediately: isMessageSeries ? scheduleImmediately : nil,
                crossPost: isMessageSeries ? crossPost : nil
            )
            created = result
            onCreated(result)
        } catch AIServiceError.unauthorized {
            authState.handleUnauthorized()
            dismiss()
        } catch let error as AIServiceError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = AIServiceError.transport.userMessage
        }
    }
}

#Preview {
    AISeriesSheet(
        feature: .messageSeries,
        input: "A launch week campaign about the new AI writing features shipping this month.",
        crossPost: AIComposerCrossPost(crossPostToBluesky: true),
        fallbackCharLimit: 666,
        onCreated: { _ in }
    )
    .environmentObject(AuthState())
}
