//
//  CreateListView.swift
//  InterlinedList
//

import SwiftUI

struct CreateListView: View {
    let onCreate: (UserList) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPublic = true
    @State private var columns: [DraftProperty] = ListSchemaDraft.starterColumns()
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !isLoading
            && !trimmedName.isEmpty
            && ListSchemaDraft.hasCreatableColumns(columns)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                    Toggle("Public", isOn: $isPublic)
                }

                Section {
                    ForEach($columns) { $column in
                        ColumnRow(column: $column, onDelete: {
                            columns.removeAll { $0.id == column.id }
                        })
                    }
                    .onMove { from, to in
                        columns.move(fromOffsets: from, toOffset: to)
                    }
                    Button {
                        columns.append(DraftProperty.newBlank())
                    } label: {
                        Label("Add Column", systemImage: "plus")
                    }
                    .accessibilityLabel("Add column")
                } header: {
                    HStack {
                        Text("Columns")
                        Spacer()
                        if columns.count > 1 {
                            EditButton()
                                .font(.ilMono())
                        }
                    }
                } footer: {
                    Text("Lists need at least one named column.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.ilMono())
                    }
                }

                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text("Create")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canCreate)
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() async {
        errorMessage = nil
        guard !trimmedName.isEmpty, ListSchemaDraft.hasCreatableColumns(columns) else { return }
        isLoading = true
        defer { isLoading = false }
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let schemaDSL = ListSchemaDraft.serializeSchemaDSL(columns)
        do {
            let list = try await APIClient.shared.createList(
                title: trimmedName,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                isPublic: isPublic,
                schema: schemaDSL.isEmpty ? nil : schemaDSL
            )
            onCreate(list)
            dismiss()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to create list."
        }
    }
}

// MARK: - Column row (name + type)

private struct ColumnRow: View {
    @Binding var column: DraftProperty
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("Column name", text: $column.propertyName)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Column name")
            Picker("Type", selection: $column.propertyType) {
                ForEach(DraftProperty.supportedTypes, id: \.self) { t in
                    Text(t.capitalized).tag(t)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Column type")
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete column \(column.propertyName.isEmpty ? "untitled" : column.propertyName)")
        }
    }
}

#Preview {
    CreateListView(onCreate: { _ in })
}
