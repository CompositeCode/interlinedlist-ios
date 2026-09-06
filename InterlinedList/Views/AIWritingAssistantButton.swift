//
//  AIWritingAssistantButton.swift
//  InterlinedList
//

import SwiftUI

/// The composer's pen menu: Rewrite / Tighten / Expand / Fix grammar / Split
/// into thread / Suggest tags. Runs `/api/ai/suggest` and presents the result.
///
/// The caller is responsible for hiding this entirely when
/// `AIService.isAvailable(for:)` is false — a free user must see no AI control at
/// all, not a disabled one (App Store Guideline 3.1.1).
struct AIWritingAssistantButton: View {
    @Binding var content: String
    /// Applies suggested tags. The composer routes them to its tags field; a
    /// reply (which has no tags field) appends them to the draft as hashtags.
    let onAddTags: ([String]) -> Void

    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var ai = AIService.shared

    @State private var isWorking = false
    @State private var suggestion: AISuggestionItem?
    @State private var errorMessage: String?

    /// Below this the assistant has nothing to work with. Mirrors the web
    /// composer's guard; the server would reject an empty input outright.
    private static let minimumWords = 2

    private var canAssist: Bool {
        AILimits.countWords(content) >= Self.minimumWords
    }

    var body: some View {
        Menu {
            ForEach(AIWritingAction.allCases) { action in
                Button {
                    Task { await run(action) }
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                }
            }
        } label: {
            if isWorking {
                ProgressView()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "pencil.and.sparkles")
                    .font(.ilBody())
                    .foregroundStyle(canAssist ? Color(ILColor.primary) : Color.secondary)
            }
        }
        .buttonStyle(.borderless)
        .disabled(isWorking || !canAssist)
        .accessibilityLabel("AI writing assistant")
        .sheet(item: $suggestion) { item in
            AISuggestionSheet(
                artifact: item.artifact,
                attribution: ai.attribution,
                onReplaceDraft: { content = $0 },
                onAddTags: onAddTags
            )
        }
        .alert("Assistant Unavailable", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await ai.loadStatusIfNeeded() }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func run(_ action: AIWritingAction) async {
        let draft = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = AILimits.countWords(draft)
        guard words >= Self.minimumWords else {
            errorMessage = "Write a little more before using the assistant."
            return
        }
        // Refuse locally rather than spending a quota unit on a request the
        // server will reject for size.
        let maxWords = AILimits.maxInputWords(.writingAssist)
        guard words <= maxWords else {
            errorMessage = "The draft is too long for the assistant (limit \(maxWords) words)."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let artifact = try await ai.suggest(
                feature: .writingAssist,
                input: draft,
                context: .writingAssist(action)
            )
            suggestion = AISuggestionItem(artifact: artifact)
        } catch AIServiceError.unauthorized {
            authState.handleUnauthorized()
        } catch let error as AIServiceError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = AIServiceError.transport.userMessage
        }
    }
}

/// `sheet(item:)` needs identity and an artifact is a plain value, so each
/// presentation carries its own.
private struct AISuggestionItem: Identifiable {
    let id = UUID()
    let artifact: AIArtifact
}

#Preview {
    Form {
        HStack {
            Text("120 characters remaining")
                .font(.ilMono())
                .foregroundStyle(.secondary)
            AIWritingAssistantButton(
                content: .constant("A short draft the assistant can work with."),
                onAddTags: { _ in }
            )
        }
    }
    .environmentObject(AuthState())
}
