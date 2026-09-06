//
//  CreateFromSheet.swift
//  InterlinedList
//

import SwiftUI

/// "Create from…" — turns a message, a list, list rows, or a document into a new
/// List, a new Document, or both (`POST /api/materialize`).
///
/// Shows exactly what will be created before anything is saved: the destination,
/// the list's columns (renameable, retypeable, removable, extendable), and a
/// preview. Only **ids** go over the wire — the server re-fetches and authorizes
/// every referenced object and re-derives each cell from that authoritative data,
/// so the preview here is advisory.
///
/// Creating lists and documents is subscriber-gated on the backend; callers must
/// hide the entry point for free users rather than present a paywall.
/// Identifiable wrapper so a `MaterializeLocalSource` can drive `.sheet(item:)`.
/// The source enum holds model values that aren't meaningfully identifiable on
/// their own, and presenting by item (rather than a bool) guarantees the sheet
/// reads the source that was current when it opened.
struct CreateFromSourceBox: Identifiable {
    let id = UUID()
    let source: MaterializeLocalSource
}

struct CreateFromSheet: View {
    let source: MaterializeLocalSource
    var onCreated: ((MaterializeResult) -> Void)?

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var target: MaterializeTarget = .list
    @State private var listTitle: String = ""
    @State private var listDescription: String = ""
    @State private var listIsPublic = false
    @State private var includeData = true
    @State private var columns: [CreateFromColumn] = []
    @State private var docTitle: String = ""
    @State private var docIsPublic = false
    @State private var listStyle: MaterializeDocListStyle = .bulleted
    @State private var rowDataStyle: MaterializeDocRowDataStyle = .inline
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var result: MaterializeResult?

    /// The server caps a materialized list at 100 columns and 1000 rows.
    private static let maxColumns = 100

    private var trimmedListTitle: String {
        listTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var namedColumns: [CreateFromColumn] {
        columns.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var wireColumns: [MaterializeFieldConfig] {
        namedColumns.enumerated().map { $0.element.config(fallbackIndex: $0.offset) }
    }

    private var duplicateKeys: [String] {
        let keys = wireColumns.map(\.propertyKey)
        return Array(Set(keys.filter { key in keys.filter { $0 == key }.count > 1 })).sorted()
    }

    private var validationProblem: String? {
        guard target.createsList else { return nil }
        if trimmedListTitle.isEmpty { return "A list title is required." }
        if namedColumns.isEmpty { return "The list needs at least one column." }
        if namedColumns.count > Self.maxColumns { return "A list can have at most \(Self.maxColumns) columns." }
        if let duplicate = duplicateKeys.first {
            return "Two columns map to the same key (\(duplicate)). Rename one."
        }
        return nil
    }

    private var canCreate: Bool {
        guard !isCreating, validationProblem == nil else { return false }
        if target.createsDocument && docTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return true
    }

    /// The doc-style pickers only affect list-shaped sources.
    private var sourceHasRows: Bool {
        switch source {
        case .lists, .rows: return true
        case .messages, .document: return false
        }
    }

    private var previewRows: [[String: String]] {
        MaterializePlanner.previewRows(for: source, fields: wireColumns)
    }

    var body: some View {
        NavigationStack {
            Form {
                destinationSection
                if let result {
                    createdSection(result)
                } else {
                    if target.createsList {
                        listDetailsSection
                        columnsSection
                        listPreviewSection
                    }
                    if target.createsDocument {
                        documentDetailsSection
                        documentPreviewSection
                    }
                    if let problem = validationProblem {
                        Section { Text(problem).font(.ilMono(12)).foregroundStyle(.red) }
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).font(.ilMono(12)).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Create from…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if result == nil {
                        Button("Create") { Task { await create() } }
                            .disabled(!canCreate)
                    }
                }
            }
            .overlay {
                if isCreating {
                    ProgressView("Creating…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear(perform: seed)
    }

    // MARK: - Sections

    private var destinationSection: some View {
        Section {
            Picker("Destination", selection: $target) {
                ForEach(MaterializeTarget.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(result != nil)
            .accessibilityLabel("What to create")
        } footer: {
            Text(sourceSummary)
        }
    }

    private var listDetailsSection: some View {
        Section("List") {
            TextField("List title", text: $listTitle)
                .accessibilityLabel("List title")
            TextField("Description (optional)", text: $listDescription, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityLabel("List description")
            Toggle("Public list", isOn: $listIsPublic)
            Toggle("Include rows", isOn: $includeData)
                .accessibilityHint("Off creates the list with its columns only")
        }
    }

    private var columnsSection: some View {
        Section {
            ForEach($columns) { $column in
                CreateFromColumnRow(column: $column)
            }
            .onDelete { columns.remove(atOffsets: $0) }
            Button {
                columns.append(CreateFromColumn())
            } label: {
                Label("Add column", systemImage: "plus")
            }
            .disabled(columns.count >= Self.maxColumns)
        } header: {
            Text("Columns")
        } footer: {
            Text("Swipe a column to remove it. Added columns start empty — the server only fills columns mapped to the source.")
        }
    }

    private var listPreviewSection: some View {
        Section {
            if !includeData {
                Text("No rows — the list will be created with its columns only.")
                    .font(.ilMono(12))
                    .foregroundStyle(.secondary)
            } else if previewRows.isEmpty {
                Text("No rows to preview.")
                    .font(.ilMono(12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(wireColumns) { column in
                                Text(column.propertyName)
                                    .font(.ilMono(11))
                                    .fontWeight(.semibold)
                                    .frame(width: 120, alignment: .leading)
                            }
                        }
                        Divider()
                        ForEach(Array(previewRows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(wireColumns) { column in
                                    Text(row[column.propertyKey] ?? "")
                                        .font(.ilMono(11))
                                        .lineLimit(3)
                                        .frame(width: 120, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("Approximate. The server rebuilds every value from your original data when it creates the list.")
        }
    }

    private var documentDetailsSection: some View {
        Section("Document") {
            TextField("Document title", text: $docTitle)
                .accessibilityLabel("Document title")
            Toggle("Public document", isOn: $docIsPublic)
            if sourceHasRows {
                Picker("List style", selection: $listStyle) {
                    ForEach(MaterializeDocListStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Picker("Row data", selection: $rowDataStyle) {
                    ForEach(MaterializeDocRowDataStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            }
        }
    }

    private var documentPreviewSection: some View {
        Section {
            Text(documentPreviewText)
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
        } header: {
            Text("Document preview")
        } footer: {
            Text("Approximate. The server writes the final markdown, and picks the file path.")
        }
    }

    private func createdSection(_ result: MaterializeResult) -> some View {
        Section("Created") {
            if let list = result.list {
                Label(list.title, systemImage: "list.bullet")
                    .accessibilityLabel("Created list \(list.title)")
            }
            if let document = result.document {
                Label(document.title, systemImage: "doc.text")
                    .accessibilityLabel("Created document \(document.title)")
            }
        }
    }

    // MARK: - Derived copy

    private var sourceSummary: String {
        switch source {
        case .messages(let messages):
            return messages.count == 1 ? "From 1 message" : "From \(messages.count) messages"
        case .lists(let lists):
            return lists.count == 1 ? "From the list “\(lists[0].listTitle)”" : "From \(lists.count) lists"
        case .rows(_, let listTitle, _, let rows):
            return rows.count == 1 ? "From 1 row of “\(listTitle)”" : "From \(rows.count) rows of “\(listTitle)”"
        case .document(let doc):
            return "From the document “\(doc.title)”"
        }
    }

    private var documentPreviewText: String {
        let rows = MaterializePlanner.previewRows(for: source, fields: wireColumns, limit: 8)
        guard !rows.isEmpty else { return "An empty document." }
        let marker = listStyle == .numbered ? "1." : "-"
        let headline = wireColumns.first?.propertyKey
        let lines = rows.prefix(8).map { row -> String in
            let text = headline.flatMap { row[$0] } ?? ""
            let first = text.components(separatedBy: .newlines).first ?? text
            return "\(marker) \(first.isEmpty ? "(empty)" : first)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    private func seed() {
        guard columns.isEmpty else { return }
        columns = MaterializePlanner.inferSchema(for: source).map(CreateFromColumn.init(from:))
        listTitle = MaterializePlanner.defaultListTitle(for: source)
        docTitle = MaterializePlanner.defaultDocumentTitle(for: source)
    }

    private func create() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let description = listDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let listConfig = MaterializeListConfig(
            title: trimmedListTitle,
            description: description.isEmpty ? nil : description,
            isPublic: listIsPublic,
            fields: wireColumns,
            includeData: includeData
        )
        let docConfig = MaterializeDocConfig(
            title: docTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            relativePath: nil,
            isPublic: docIsPublic,
            listStyle: sourceHasRows ? listStyle : nil,
            rowDataStyle: sourceHasRows ? rowDataStyle : nil
        )

        do {
            let created = try await APIClient.shared.materialize(
                target: target,
                source: MaterializePlanner.sourceRef(for: source),
                listConfig: listConfig,
                docConfig: docConfig
            )
            result = created
            onCreated?(created)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "Your session expired. Try again."
        } catch APIError.status(403), APIError.forbidden {
            // Never surface the raw 403 body — it carries "Subscribe…" upsell copy
            // that must not appear in-app (Guideline 3.1.1).
            errorMessage = "Creating lists and documents is a subscriber feature."
        } catch APIError.status(404) {
            errorMessage = "Something this would be built from is no longer available."
        } catch APIError.server(let text) {
            errorMessage = text
        } catch {
            errorMessage = "Couldn't create that. Try again."
        }
    }
}

#Preview("From a message") {
    CreateFromSheet(source: .messages([
        Message(
            id: "m1", content: "Tacos in Seattle — where?\nAsking for a friend.",
            publiclyVisible: true, userId: "u1", createdAt: "2026-09-01T12:00:00Z", updatedAt: nil,
            user: MessageUser(id: "u1", username: "adron", displayName: "Adron", avatar: nil),
            imageUrls: nil, videoUrls: nil, linkMetadata: nil, parentId: nil, scheduledAt: nil,
            tags: ["food", "seattle"], digCount: 3, dugByMe: false, crossPostUrls: nil
        )
    ]))
    .environmentObject(AuthState())
}

#Preview("From a document") {
    CreateFromSheet(source: .document(MaterializeDocumentSummary(
        documentId: "d1",
        title: "Reading list",
        content: "# Books\n\n- Dune\n- Neuromancer\n\n## Later\n\n- Snow Crash"
    )))
    .environmentObject(AuthState())
}
