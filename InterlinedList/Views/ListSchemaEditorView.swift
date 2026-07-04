//
//  ListSchemaEditorView.swift
//  InterlinedList
//

import SwiftUI

struct ListSchemaEditorView: View {
    let list: UserList
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
    @State private var showForceDeleteConfirm = false
    @State private var conflictMessage: String?

    private let originalTitle: String
    private let originalDescription: String
    private let originalIsPublic: Bool
    private let originalProperties: [DraftProperty]

    init(list: UserList, schema: [ListPropertyDef], onSave: @escaping (UserList) -> Void) {
        self.list = list
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
        ListSchemaDraft.isTitleValid(title)
    }

    private var schemaChanged: Bool {
        ListSchemaDraft.schemaChanged(original: originalProperties, current: properties)
    }

    private var metadataChanged: Bool {
        ListSchemaDraft.metadataChanged(
            originalTitle: originalTitle,
            originalDescription: originalDescription,
            originalIsPublic: originalIsPublic,
            title: title,
            description: description,
            isPublic: isPublic
        )
    }

    private var isSchemaValid: Bool {
        ListSchemaDraft.isSchemaValid(properties)
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
                            .font(.ilMono())
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
                            .font(.ilBody(15))
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
                                .font(.ilMono())
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.ilMono())
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
                        .disabled(!isTitleValid || (!metadataChanged && !schemaChanged) || !isSchemaValid)
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
            .confirmationDialog(
                "Some columns still contain data",
                isPresented: $showForceDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete anyway", role: .destructive) {
                    Task { await save(force: true) }
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text(conflictMessage ?? "Deleting these properties will remove their values from every row.")
            }
            .alert("Save Failed", isPresented: .constant(errorMessage != nil && !isSaving), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    private func save(force: Bool = false) async {
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
            if schemaChanged {
                // Structured form (GAP §B0): round-trips isVisible / isRequired /
                // order. New rows are created, existing rows updated in place, and
                // omitted properties soft-deleted. `force` confirms dropping a
                // column that still has data (the server returns 409 otherwise).
                let structured = ListSchemaDraft.structuredProperties(properties)
                _ = try await APIClient.shared.updateListSchemaStructured(
                    listId: list.id, properties: structured, force: force)
            }
            onSave(updated)
            dismiss()
        } catch APIError.conflict(let msg) {
            conflictMessage = msg
            showForceDeleteConfirm = true
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
                    .font(.ilMono())
                Spacer()
                Toggle("Required", isOn: $property.isRequired)
                    .toggleStyle(.switch)
                    .font(.ilMono())
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
