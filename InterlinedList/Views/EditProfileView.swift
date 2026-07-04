//
//  EditProfileView.swift
//  InterlinedList
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var bio: String
    @State private var defaultPublic: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var currentAvatarURL: String?
    @State private var avatarActionSheetPresented = false
    @State private var avatarURLEntryPresented = false
    @State private var photosPickerPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isAvatarUploading = false
    @State private var avatarError: String?

    @State private var changeEmailPresented = false
    @State private var deleteFirstAlertPresented = false
    @State private var deleteConfirmAlertPresented = false
    @State private var deleteConfirmationText = ""
    @State private var deleteErrorAlertPresented = false
    @State private var isDeletingAccount = false

    init(user: User) {
        _displayName = State(initialValue: user.displayName ?? "")
        _bio = State(initialValue: user.bio ?? "")
        _defaultPublic = State(initialValue: user.defaultPubliclyVisible ?? true)
        _currentAvatarURL = State(initialValue: user.avatar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    avatarRow
                } header: {
                    Text("Profile Picture")
                } footer: {
                    if let avatarError {
                        Text(avatarError)
                            .foregroundStyle(.red)
                    }
                }

                Section("Identity") {
                    TextField("Display name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Account") {
                    Button {
                        changeEmailPresented = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .foregroundStyle(.primary)
                                Text(authState.user?.email ?? "")
                                    .font(.ilBody(15))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Change")
                                .font(.ilBody(15))
                                .foregroundStyle(ILColor.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change email address")
                }
                Section("Defaults") {
                    Toggle("Default post visibility: Public", isOn: $defaultPublic)
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
                        Task { await save() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().frame(width: 20, height: 20) }
                            Text("Save Changes").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading)
                }

                Section {
                    Button(role: .destructive) {
                        deleteFirstAlertPresented = true
                    } label: {
                        HStack {
                            if isDeletingAccount { ProgressView().frame(width: 20, height: 20) }
                            Text("Delete Account").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isDeletingAccount)
                    .accessibilityLabel("Delete account")
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently removes your account and all associated data.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Change profile picture", isPresented: $avatarActionSheetPresented, titleVisibility: .visible) {
                Button("Choose Photo") {
                    photosPickerPresented = true
                }
                Button("Use URL") {
                    avatarURLEntryPresented = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $photosPickerPresented, selection: $selectedPhoto, matching: .images)
            .sheet(isPresented: $avatarURLEntryPresented) {
                AvatarURLEntryView { urlString in
                    Task { await setAvatarFromURL(urlString) }
                }
            }
            .sheet(isPresented: $changeEmailPresented) {
                ChangeEmailView()
                    .environmentObject(authState)
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await uploadAvatar(newItem) }
            }
            .alert("Delete your account?", isPresented: $deleteFirstAlertPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    deleteConfirmationText = ""
                    deleteConfirmAlertPresented = true
                }
            } message: {
                Text("This will permanently delete your account and all your data. This cannot be undone.")
            }
            .alert("Type DELETE to confirm", isPresented: $deleteConfirmAlertPresented) {
                TextField("DELETE", text: $deleteConfirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {
                    deleteConfirmationText = ""
                }
                Button("Delete", role: .destructive) {
                    if deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE" {
                        Task { await deleteAccount() }
                    } else {
                        deleteConfirmationText = ""
                    }
                }
            } message: {
                Text("Enter DELETE in all caps to permanently remove your account.")
            }
            .alert("Couldn't delete account", isPresented: $deleteErrorAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Couldn't delete account. Try again later.")
            }
        }
    }

    @ViewBuilder
    private var avatarRow: some View {
        HStack(spacing: 16) {
            avatarImage
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
                .accessibilityLabel("Profile picture")
                .accessibilityHint("Change your profile picture")

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    avatarActionSheetPresented = true
                } label: {
                    Text(isAvatarUploading ? "Uploading…" : "Change Photo")
                }
                .disabled(isAvatarUploading)

                if isAvatarUploading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isAvatarUploading {
                avatarActionSheetPresented = true
            }
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlString = currentAvatarURL,
           let url = URL(string: urlString),
           !urlString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholderAvatar
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholderAvatar
                }
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            ILColor.surface2
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(4)
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

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isAvatarUploading = true
        avatarError = nil
        defer {
            isAvatarUploading = false
            selectedPhoto = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                avatarError = "Couldn't upload avatar."
                return
            }
            let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let updated = try await APIClient.shared.uploadAvatar(data: data, mimeType: mimeType)
            authState.updateUser(updated)
            currentAvatarURL = updated.avatar
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            avatarError = "Couldn't upload avatar."
        }
    }

    private func setAvatarFromURL(_ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAvatarUploading = true
        avatarError = nil
        defer { isAvatarUploading = false }
        do {
            let updated = try await APIClient.shared.setAvatarFromURL(trimmed)
            authState.updateUser(updated)
            currentAvatarURL = updated.avatar
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            avatarError = "Couldn't upload avatar."
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await APIClient.shared.deleteAccount()
            authState.logout()
        } catch {
            deleteErrorAlertPresented = true
        }
    }
}

private struct AvatarURLEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlString: String = ""
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/avatar.jpg", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Avatar image URL")
                } footer: {
                    Text("Paste a direct link to an image.")
                }
            }
            .navigationTitle("Use Image URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSubmit(trimmed)
                        dismiss()
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    EditProfileView(user: User(
        id: "1", email: "test@example.com", username: "testuser",
        displayName: "Test User", avatar: nil, bio: "Hello world",
        theme: nil, emailVerified: true, createdAt: nil,
        maxMessageLength: nil, showAdvancedPostSettings: nil,
        defaultPubliclyVisible: true, customerStatus: nil
    ))
    .environmentObject(AuthState())
}
