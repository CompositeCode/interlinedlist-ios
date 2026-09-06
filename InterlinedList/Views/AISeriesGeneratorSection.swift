//
//  AISeriesGeneratorSection.swift
//  InterlinedList
//

import SwiftUI

/// The composer's two series generators. Both stay inert until the draft holds
/// at least `AILimits.composerMinWords` words — the server rejects anything
/// shorter, and a rejected call still costs a quota unit.
///
/// The caller hides this section entirely for anyone without the AI entitlement.
struct AISeriesGeneratorSection: View {
    let content: String
    /// The composer's live cross-post selection, forwarded to the sheet.
    let crossPost: AIComposerCrossPost
    let maxMessageLength: Int
    let onCreated: (AICreated) -> Void

    @State private var activeFeature: AIFeature?

    private var wordCount: Int {
        AILimits.countWords(content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isReady: Bool { wordCount >= AILimits.composerMinWords }

    var body: some View {
        Section {
            Button {
                activeFeature = .messageSeries
            } label: {
                Label("Message Series", systemImage: "text.bubble")
            }
            .disabled(!isReady)
            .accessibilityLabel("Generate a message series")

            Button {
                activeFeature = .articleSeries
            } label: {
                Label("Article Series", systemImage: "doc.text.below.ecg")
            }
            .disabled(!isReady)
            .accessibilityLabel("Generate an article series")
        } header: {
            Text("Generate a Series")
        } footer: {
            Text(isReady
                 ? "Drafts a set of posts or documents from what you've written. You'll review before anything is created."
                 : "Write at least \(AILimits.composerMinWords) words to generate a series (\(wordCount) so far).")
                .font(.ilMono())
        }
        .sheet(item: $activeFeature) { feature in
            AISeriesSheet(
                feature: feature,
                input: content.trimmingCharacters(in: .whitespacesAndNewlines),
                crossPost: crossPost,
                fallbackCharLimit: maxMessageLength,
                onCreated: onCreated
            )
        }
    }
}

#Preview {
    Form {
        AISeriesGeneratorSection(
            content: "A launch week campaign about the AI writing features shipping this month.",
            crossPost: AIComposerCrossPost(crossPostToBluesky: true),
            maxMessageLength: 666,
            onCreated: { _ in }
        )
    }
    .environmentObject(AuthState())
}
