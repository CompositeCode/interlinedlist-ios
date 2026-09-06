//
//  AIPoweredTemplateView.swift
//  InterlinedList
//

import SwiftUI

/// Powered Templates: describe a list in plain language and the AI drafts its
/// schema and starter rows. Runs the same suggest → preview → confirm →
/// generate flow as the rest of the AI surface.
///
/// The generated list is created server-side from the artifact verbatim, so
/// column types the iOS schema editor can't express (select, multiselect, and
/// their options) survive intact; the schema is editable afterwards in the list.
struct AIPoweredTemplateView: View {
    let onCreate: (UserList?) -> Void

    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var ai = AIService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateId: String?
    @State private var prompt = ""
    @State private var artifact: AIListArtifact?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var canRetry = false

    private var selectedTemplate: AIPoweredTemplate? {
        AIPoweredTemplate.gallery.first { $0.id == selectedTemplateId }
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var promptWordCount: Int { AILimits.countWords(trimmedPrompt) }

    private var isPromptValid: Bool {
        !trimmedPrompt.isEmpty && promptWordCount <= AILimits.maxInputWords(.poweredTemplate)
    }

    var body: some View {
        Group {
            if let artifact {
                previewForm(artifact)
            } else {
                promptForm
            }
        }
        .task { await ai.loadStatusIfNeeded() }
    }

    // MARK: - Prompt

    private var promptForm: some View {
        Form {
            Section {
                ForEach(AIPoweredTemplate.gallery) { template in
                    Button {
                        selectedTemplateId = (selectedTemplateId == template.id) ? nil : template.id
                    } label: {
                        templateRow(template)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(template.name) template\(selectedTemplateId == template.id ? ", selected" : "")")
                }
            } header: {
                Text("Start From")
            } footer: {
                Text("Optional — a template steers the shape. Skip it and the description alone decides.")
                    .font(.ilMono())
            }

            Section {
                TextField(
                    selectedTemplate?.promptPlaceholder ?? "e.g. Track conference talks: event, date, status, slides URL",
                    text: $prompt,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .accessibilityLabel("Describe the list to build")
            } header: {
                Text("Describe Your List")
            } footer: {
                if promptWordCount > AILimits.maxInputWords(.poweredTemplate) {
                    Text("Too long — keep it under \(AILimits.maxInputWords(.poweredTemplate)) words.")
                        .font(.ilMono())
                        .foregroundStyle(.red)
                } else {
                    Text("Describe what you want to track and the columns are tailored to it.")
                        .font(.ilMono())
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
                        Text(isWorking ? "Drafting schema…" : "Draft Schema")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isWorking || !isPromptValid)
            } footer: {
                quotaFooter
            }
        }
    }

    @ViewBuilder
    private func templateRow(_ template: AIPoweredTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(template.icon)
                .font(.system(size: 26))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(template.summary)
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
                Text(template.previewChips.joined(separator: " · "))
                    .font(.ilMono())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if selectedTemplateId == template.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color(ILColor.primary))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Preview

    private func previewForm(_ artifact: AIListArtifact) -> some View {
        Form {
            Section {
                Text(artifact.title)
                    .font(.ilBody(15))
                    .fontWeight(.medium)
                if let description = artifact.description, !description.isEmpty {
                    Text(description)
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("List")
            }

            Section {
                ForEach(artifact.fields) { field in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label)
                                .font(.ilBody(15))
                            if !field.options.isEmpty {
                                Text(field.options.joined(separator: " · "))
                                    .font(.ilMono())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(field.type)
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(field.label), \(field.type)\(field.isRequired ? ", required" : "")")
                }
            } header: {
                Text("Columns")
            }

            if let rows = artifact.rows, !rows.isEmpty {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(artifact.rowSummary(row), id: \.label) { pair in
                                Text("\(pair.label): \(pair.value)")
                                    .font(.ilMono())
                            }
                        }
                    }
                } header: {
                    Text("Starter Rows")
                }
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
                        Text("Create List")
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
                    Text("Created as a private list. You can edit the columns and sharing afterwards.")
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

    private func generate() async {
        guard isPromptValid, !isWorking else { return }
        errorMessage = nil
        canRetry = false
        isWorking = true
        defer { isWorking = false }
        do {
            let suggestion = try await ai.suggest(
                feature: .poweredTemplate,
                input: trimmedPrompt,
                context: .poweredTemplate(templateKey: selectedTemplateId)
            )
            guard case .list(let list) = suggestion else {
                errorMessage = AIServiceError.invalidOutput.userMessage
                canRetry = true
                return
            }
            artifact = list
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

    private func create(_ list: AIListArtifact) async {
        guard !isWorking else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await ai.generate(feature: .poweredTemplate, artifact: .list(list))
            // `/generate` returns only the id, so resolve the real list for the
            // caller. A failed lookup still counts as created — `nil` tells the
            // caller to refresh rather than that nothing happened.
            var resolved: UserList?
            if let id = created.listId {
                resolved = (try? await APIClient.shared.lists())?.first { $0.id == id }
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
    NavigationStack {
        AIPoweredTemplateView(onCreate: { _ in })
    }
    .environmentObject(AuthState())
}
