//
//  EditProfileView.swift
//  InterlinedList
//

import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var bio: String
    @State private var defaultPublic: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(user: User) {
        _displayName = State(initialValue: user.displayName ?? "")
        _bio = State(initialValue: user.bio ?? "")
        _defaultPublic = State(initialValue: user.defaultPubliclyVisible ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Defaults") {
                    Toggle("Default post visibility: Public", isOn: $defaultPublic)
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
                        Task { await save() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().frame(width: 20, height: 20) }
                            Text("Save Changes").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await APIClient.shared.updateProfile(
                displayName: trimmedName.isEmpty ? nil : trimmedName,
                bio: trimmedBio.isEmpty ? nil : trimmedBio,
                defaultVisibility: defaultPublic
            )
            authState.updateUser(updated)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Could not save profile. Please try again."
        }
    }
}

#Preview {
    EditProfileView(user: User(
        id: "1", email: "test@example.com", username: "testuser",
        displayName: "Test User", avatar: nil, bio: "Hello world",
        theme: nil, emailVerified: true, createdAt: nil,
        maxMessageLength: nil, showAdvancedPostSettings: nil,
        defaultPubliclyVisible: true, isSubscriber: nil
    ))
    .environmentObject(AuthState())
}
