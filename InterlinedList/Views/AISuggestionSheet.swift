//
//  AISuggestionSheet.swift
//  InterlinedList
//

import SwiftUI

/// Renders one Writing Assistant suggestion and hands it back to the composer.
/// Presentation only — the caller decides what "apply" means for its own draft.
struct AISuggestionSheet: View {
    let artifact: AIArtifact
    let attribution: String?
    let onReplaceDraft: (String) -> Void
    let onAddTags: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    content
                } footer: {
                    if let attribution {
                        Text(attribution)
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(applyLabel) { apply() }
                        .accessibilityLabel(applyLabel)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        switch artifact {
        case .thread(let parts): return "Thread · \(parts.count) parts"
        case .tags: return "Suggested Tags"
        default: return "Suggestion"
        }
    }

    private var applyLabel: String {
        switch artifact {
        case .thread: return "Use in Draft"
        case .tags: return "Add Tags"
        default: return "Replace Draft"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch artifact {
        case .message(let text):
            Text(text)
                .font(.ilBody(15))
                .textSelection(.enabled)
        case .thread(let parts):
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Part \(index + 1)")
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                    Text(part)
                        .font(.ilBody(15))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Part \(index + 1): \(part)")
            }
        case .tags(let tags):
            ForEach(tags, id: \.self) { tag in
                Label("#\(tag)", systemImage: "number")
                    .font(.ilBody(15))
            }
        case .document, .messageSeries, .docSeries, .list:
            // The Writing Assistant only ever produces message / thread / tags.
            Text("This suggestion can't be applied to the draft.")
                .font(.ilBody(15))
                .foregroundStyle(.secondary)
        }
    }

    private func apply() {
        switch artifact {
        case .message(let text):
            onReplaceDraft(text)
        case .thread(let parts):
            onReplaceDraft(parts.joined(separator: "\n\n"))
        case .tags(let tags):
            onAddTags(tags)
        case .document, .messageSeries, .docSeries, .list:
            break
        }
        dismiss()
    }
}

#Preview {
    AISuggestionSheet(
        artifact: .thread(["Opening line of the thread.", "The follow-up that carries the argument."]),
        attribution: "Powered by Claude Sonnet 5",
        onReplaceDraft: { _ in },
        onAddTags: { _ in }
    )
}
