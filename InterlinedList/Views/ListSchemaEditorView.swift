//
//  ListSchemaEditorView.swift
//  InterlinedList
//

import SwiftUI

struct ListSchemaEditorView: View {
    let list: UserList
    let initialSchema: [ListPropertyDef]
    let onSave: (UserList) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    @State private var title: String
    @State private var description: String
    @State private var isPublic: Bool
    @State private var properties: [DraftProperty]

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showUnsavedConfirm = false

    private let originalTitle: String
    private let originalDescription: String
    private let originalIsPublic: Bool
    private let originalProperties: [DraftProperty]

    init(list: UserList, schema: [ListPropertyDef], onSave: @escaping (UserList) -> Void) {
        self.list = list
        self.initialSchema = schema
        self.onSave = onSave

        let initialTitle = list.name
        let initialDesc = list.description ?? ""
        let initialPublic = list.isPublic ?? false
        let drafts = schema
            .sorted { $0.displayOrder < $1.displayOrder }
            .map { DraftProperty(from: $0) }

        _title = State(initialValue: initialTitle)
        _description = State(initialValue: initialDesc)
        _isPublic = State(initialValue: initialPublic)
        _properties = State(initialValue: drafts)

        self.originalTitle = initialTitle
        self.originalDescription = initialDesc
        self.originalIsPublic = initialPublic
        self.originalProperties = drafts
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTitleValid: Bool {
        let count = trimmedTitle.count
        return count >= 1 && count <= 120
    }

    private var schemaChanged: Bool {
        properties != originalProperties
    }

    private var metadataChanged: Bool {
        trimmedTitle != originalTitle
            || trimmedDescription != originalDescription
            || isPublic != originalIsPublic
    }

    private var hasUnsavedChanges: Bool {
        metadataChanged || schemaChanged
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .accessibilityLabel("List title")
                    if !isTitleValid {
                        Text("Title must be 1–120 characters.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Description") {
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityLabel("List description")
                }

                Section("Visibility") {
                    Toggle("Public", isOn: $isPublic)
                        .accessibilityLabel("Public visibility")
                }

                Section {
                    if properties.isEmpty {
                        Text("No properties defined.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach($properties) { $prop in
                            PropertyRow(property: $prop, onDelete: {
                                properties.removeAll { $0.id == prop.id }
                            })
                        }
                        .onMove { from, to in
                            properties.move(fromOffsets: from, toOffset: to)
                        }
                    }
                    Button {
                        properties.append(DraftProperty.newBlank())
                    } label: {
                        Label("Add Property", systemImage: "plus")
                    }
                    .accessibilityLabel("Add new property")
                } header: {
                    HStack {
                        Text("Schema")
                        Spacer()
                        if !properties.isEmpty {
                            EditButton()
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text("Schema editing is not yet supported by the backend; property changes will not be saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showUnsavedConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityLabel("Cancel editing")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("Saving")
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!isTitleValid || !metadataChanged)
                        .accessibilityLabel("Save list changes")
                    }
                }
            }
            .confirmationDialog(
                "Discard unsaved changes?",
                isPresented: $showUnsavedConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Save Failed", isPresented: .constant(errorMessage != nil && !isSaving), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    private func save() async {
        guard isTitleValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await APIClient.shared.updateList(
                id: list.id,
                title: trimmedTitle,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                isPublic: isPublic
            )
            // TODO: backend schema update endpoint — once PUT /api/lists/[id]/schema
            // (or a non-destructive equivalent) is exposed in APIClient, persist
            // `properties` here in the same save action.
            onSave(updated)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "Session expired. Please sign in again."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to update list."
        }
    }
}

// MARK: - Draft property model

private struct DraftProperty: Identifiable, Equatable {
    let id: String
    var propertyKey: String
    var propertyName: String
    var propertyType: String
    var isVisible: Bool
    var isRequired: Bool

    static let supportedTypes: [String] = ["text", "number", "boolean", "date", "url", "email"]

    init(from def: ListPropertyDef) {
        self.id = def.id
        self.propertyKey = def.propertyKey
        self.propertyName = def.propertyName
        self.propertyType = def.propertyType
        self.isVisible = def.isVisible
        self.isRequired = def.isRequired
    }

    private init(id: String, propertyKey: String, propertyName: String, propertyType: String, isVisible: Bool, isRequired: Bool) {
        self.id = id
        self.propertyKey = propertyKey
        self.propertyName = propertyName
        self.propertyType = propertyType
        self.isVisible = isVisible
        self.isRequired = isRequired
    }

    static func newBlank() -> DraftProperty {
        DraftProperty(
            id: "new-" + UUID().uuidString,
            propertyKey: "",
            propertyName: "",
            propertyType: "text",
            isVisible: true,
            isRequired: false
        )
    }
}

// MARK: - Property row

private struct PropertyRow: View {
    @Binding var property: DraftProperty
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $property.propertyName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Property name")
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete property \(property.propertyName.isEmpty ? "untitled" : property.propertyName)")
            }
            HStack {
                Picker("Type", selection: $property.propertyType) {
                    ForEach(DraftProperty.supportedTypes, id: \.self) { t in
                        Text(t.capitalized).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Property type")
            }
            HStack {
                Toggle("Visible", isOn: $property.isVisible)
                    .toggleStyle(.switch)
                    .font(.caption)
                Spacer()
                Toggle("Required", isOn: $property.isRequired)
                    .toggleStyle(.switch)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Schema editor") {
    let mockList = UserList(
        id: "list-1",
        name: "Books to Read",
        description: "Personal reading queue",
        folderId: nil,
        isPublic: false,
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: nil,
        itemCount: 12
    )
    let mockSchema: [ListPropertyDef] = [
        ListPropertyDef(id: "p1", propertyKey: "title", propertyName: "Title", propertyType: "text",
                        displayOrder: 0, isVisible: true, isRequired: true,
                        defaultValue: nil, helpText: nil, placeholder: nil),
        ListPropertyDef(id: "p2", propertyKey: "read", propertyName: "Have Read", propertyType: "boolean",
                        displayOrder: 1, isVisible: true, isRequired: false,
                        defaultValue: nil, helpText: nil, placeholder: nil),
    ]
    return ListSchemaEditorView(list: mockList, schema: mockSchema, onSave: { _ in })
        .environmentObject(AuthState())
}
