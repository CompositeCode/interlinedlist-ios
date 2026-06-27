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
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                    Toggle("Public", isOn: $isPublic)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
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
                    .disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        isLoading = true
        defer { isLoading = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let list = try await APIClient.shared.createList(
                title: trimmedName,
                description: trimmedDesc.isEmpty ? nil : trimmedDesc,
                isPublic: isPublic
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

#Preview {
    CreateListView(onCreate: { _ in })
}
