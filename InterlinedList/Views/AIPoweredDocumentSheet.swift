//
//  AIPoweredDocumentSheet.swift
//  InterlinedList
//

import SwiftUI

/// Powered Document — four ways to draft a document: from a topic, from one of
/// your lists, from an existing document, or from a web page.
///
/// Derived modes send **ids only**; the server re-fetches and authorizes each
/// source itself (and guards the URL fetch), so nothing here has to ship the
/// source content. The document is created at the root, which is why the entry
/// point lives on the Documents root rather than inside a folder.
struct AIPoweredDocumentSheet: View {
    let onCreate: (Document?) -> Void

    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var store: AppDataStore
    @ObservedObject private var ai = AIService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AIDocumentMode = .article
    @State private var instruction = ""
    @State private var selectedListId: String?
    @State private var selectedDocumentId: String?
    @State private var url = ""
    @State private var lists: [UserList] = []
    @State private var artifact: AIDocumentArtifact?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var canRetry = false

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        guard AILimits.countWords(trimmedInstruction) <= AILimits.maxInputWords(.poweredDocument) else {
            return false
        }
        switch mode {
        case .article: return !trimmedInstruction.isEmpty
        case .fromList: return selectedListId != nil
        case .fromArticle: return selectedDocumentId != nil
        case .researchUrl: return isValidHTTPURL(trimmedURL)
        }
    }

    private func isValidHTTPURL(_ candidate: String) -> Bool {
        guard let parsed = URL(string: candidate), let scheme = parsed.scheme?.lowercased() else {
            return false
        }
        return (scheme == "http" || scheme == "https") && (parsed.host?.isEmpty == false)
    }

    /// Mirrors the web's per-mode default instruction.
    private var effectiveInput: String {
        if !trimmedInstruction.isEmpty { return trimmedInstruction }
        switch mode {
        case .article: return trimmedInstruction
        case .researchUrl: return "Write a document about this page."
        case .fromList, .fromArticle: return "Write a coherent document from this source."
        }
    }

    private var context: AIContext {
        switch mode {
        case .article:
            return .poweredDocument(mode: .article)
        case .fromList:
            return .poweredDocument(mode: .fromList, listId: selectedListId)
        case .fromArticle:
            return .poweredDocument(mode: .fromArticle, documentId: selectedDocumentId)
        case .researchUrl:
            return .poweredDocument(mode: .researchUrl, url: trimmedURL)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let artifact {
                    previewForm(artifact)
                } else {
                    inputForm
                }
            }
            .navigationTitle("Powered Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await ai.loadStatusIfNeeded()
                await loadLists()
            }
        }
    }

    // MARK: - Input

    private var inputForm: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(AIDocumentMode.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                }
                .accessibilityLabel("Document source")
                sourcePicker
            } header: {
                Text("Source")
            } footer: {
                Text(sourceFooter)
                    .font(.ilMono())
            }

            Section {
                TextField(instructionPlaceholder, text: $instruction, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityLabel("Instruction")
            } header: {
                Text(mode == .article ? "What Should It Cover?" : "Instruction (Optional)")
            } footer: {
                if AILimits.countWords(trimmedInstruction) > AILimits.maxInputWords(.poweredDocument) {
                    Text("Too long — keep it under \(AILimits.maxInputWords(.poweredDocument)) words.")
                        .font(.ilMono())
                        .foregroundStyle(.red)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.ilBody(15))
                        .foregroundStyle(.red)
                    if canRetry {
                        Button("Try Again") { Task { await generate() } }
                            .disabled(isWorking)
                    }
                }
            }

            Section {
                Button {
                    Task { await generate() }
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView().frame(width: 20, height: 20)
                        }
                        Text(isWorking ? "Drafting…" : "Draft Document")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isWorking || !canGenerate)
            } footer: {
                quotaFooter
            }
        }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        switch mode {
        case .article:
            EmptyView()
        case .fromList:
            Picker("List", selection: $selectedListId) {
                Text("Select a list").tag(String?.none)
                ForEach(lists) { list in
                    Text(list.name).tag(String?.some(list.id))
                }
            }
            .accessibilityLabel("Source list")
        case .fromArticle:
            Picker("Document", selection: $selectedDocumentId) {
                Text("Select a document").tag(String?.none)
                ForEach(store.documents) { document in
                    Text(document.title).tag(String?.some(document.id))
                }
            }
            .accessibilityLabel("Source document")
        case .researchUrl:
            TextField("https://…", text: $url)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityLabel("Source URL")
        }
    }

    private var sourceFooter: String {
        switch mode {
        case .article: return "Drafts a document from your description alone."
        case .fromList: return "Narrates one of your lists. The server reads the rows — no rows are invented."
        case .fromArticle: return "Rewrites one of your documents: summarize, expand, or restructure."
        case .researchUrl: return "Reads a public web page and writes about it, citing the source."
        }
    }

    private var instructionPlaceholder: String {
        mode == .article
            ? "Draft a runbook for our deploy process…"
            : "Summarize, expand, restructure…"
    }

    // MARK: - Preview

    private func previewForm(_ artifact: AIDocumentArtifact) -> some View {
        Form {
            Section {
                Text(artifact.title)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
            } header: {
                Text("Title")
            }

            if let outline = artifact.outline, !outline.isEmpty {
                Section {
                    ForEach(Array(outline.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.ilMono())
                    }
                } header: {
                    Text("Outline")
                }
            }

            Section {
                Text(artifact.markdown)
                    .font(.ilBody(14))
                    .textSelection(.enabled)
            } header: {
                Text("Draft")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.ilBody(15))
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await create(artifact) }
                } label: {
                    HStack {
                        if isWorking {
                            ProgressView().frame(width: 20, height: 20)
                        }
                        Text("Create Document")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isWorking)
                Button("Start Over") {
                    self.artifact = nil
                    errorMessage = nil
                }
                .disabled(isWorking)
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created as a private document you can edit afterwards.")
                    quotaFooter
                }
            }
        }
    }

    @ViewBuilder
    private var quotaFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let quota = ai.quota {
                Text("\(quota.remaining) of \(quota.dailyLimit) AI runs left today.")
            }
            if let attribution = ai.attribution {
                Text(attribution)
            }
        }
        .font(.ilMono())
    }

    // MARK: - Actions

    private func loadLists() async {
        guard lists.isEmpty else { return }
        lists = store.userLists.isEmpty ? ((try? await APIClient.shared.lists()) ?? []) : store.userLists
    }

    private func generate() async {
        guard canGenerate, !isWorking else { return }
        errorMessage = nil
        canRetry = false
        isWorking = true
        defer { isWorking = false }
        do {
            let suggestion = try await ai.suggest(
                feature: .poweredDocument,
                input: effectiveInput,
                context: context
            )
            guard case .document(let document) = suggestion else {
                errorMessage = AIServiceError.invalidOutput.userMessage
                canRetry = true
                return
            }
            artifact = document
        } catch AIServiceError.unauthorized {
            authState.handleUnauthorized()
        } catch let error as AIServiceError {
            errorMessage = error.userMessage
            canRetry = error.isRetryable
        } catch {
            errorMessage = AIServiceError.transport.userMessage
            canRetry = true
        }
    }

    private func create(_ document: AIDocumentArtifact) async {
        guard !isWorking else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await ai.generate(feature: .poweredDocument, artifact: .document(document))
            // `/generate` returns only the id; resolve the real document so the
            // caller can open it. `nil` means "created, but refresh to see it".
            var resolved: Document?
            if let id = created.documentId {
                resolved = (try? await APIClient.shared.documents())?.first { $0.id == id }
            }
            onCreate(resolved)
            dismiss()
        } catch AIServiceError.unauthorized {
            authState.handleUnauthorized()
        } catch let error as AIServiceError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = AIServiceError.transport.userMessage
        }
    }
}

#Preview {
    AIPoweredDocumentSheet(onCreate: { _ in })
        .environmentObject(AuthState())
        .environmentObject(AppDataStore())
}
