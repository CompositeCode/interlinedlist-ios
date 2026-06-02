//
//  ComposeView.swift
//  InterlinedList
//

import SwiftUI
import PhotosUI

/// Fallback when user's maxMessageLength is not available (matches API default).
private let defaultMaxMessageLength = 666

struct ComposeView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    /// When set, this view posts a reply to the given message.
    var replyTo: Message? = nil
    @State private var content = ""
    @State private var tags = ""
    @State private var publiclyVisible = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showAdvancedBar = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var uploadedImageURL: String?
    @State private var isUploadingImage = false
    @State private var selectedVideo: PhotosPickerItem?
    @State private var uploadedVideoURL: String?
    @State private var isUploadingVideo = false
    @State private var scheduledDate: Date?
    @State private var showSchedulePicker = false

    private var isReply: Bool { replyTo != nil }

    /// Apply user's default settings for public visibility and advanced bar. Call when view appears (new post) or after successful post.
    private func applyUserDefaults() {
        guard !isReply else { return }
        publiclyVisible = authState.user?.defaultPubliclyVisible ?? true
        showAdvancedBar = authState.user?.showAdvancedPostSettings ?? false
    }
    private var maxMessageLength: Int { authState.user?.maxMessageLength ?? defaultMaxMessageLength }
    private var remainingCharacters: Int { max(0, maxMessageLength - content.count) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isReply ? "Write a reply…" : "What's on your mind?", text: $content, axis: .vertical)
                        .lineLimit(5...15)
                    if !isReply {
                        TextField("Tags (comma-separated)", text: $tags)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !isReply {
                        advancedToolbar
                        Toggle("Public", isOn: $publiclyVisible)
                    }
                    if showSchedulePicker && !isReply {
                        schedulePicker
                    }
                    if let url = uploadedImageURL {
                        uploadedImagePreview(url: url)
                    }
                    if let url = uploadedVideoURL {
                        uploadedVideoPreview(url: url)
                    }
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
                        Task { await postMessage() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            }
                            Text(scheduledDate != nil ? "Schedule" : (isReply ? "Reply" : "Post"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isReply ? "Reply" : "New post")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                applyUserDefaults()
            }
            .alert(isReply ? "Replied" : (scheduledDate != nil ? "Scheduled" : "Posted"), isPresented: $showSuccess) {
                Button("OK") {
                    content = ""
                    uploadedImageURL = nil
                    selectedPhoto = nil
                    uploadedVideoURL = nil
                    selectedVideo = nil
                    scheduledDate = nil
                    showSchedulePicker = false
                    applyUserDefaults()
                }
            } message: {
                Text(isReply ? "Your reply was posted." : (scheduledDate != nil ? "Your message has been scheduled." : "Your message was posted."))
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await uploadPhoto(newItem) }
            }
        }
    }

    @ViewBuilder
    private var advancedToolbar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("\(remainingCharacters) characters remaining")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showAdvancedBar.toggle()
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showAdvancedBar ? 90 : 0))
            }
            .buttonStyle(.borderless)
            if showAdvancedBar {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        if isUploadingImage {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: uploadedImageURL != nil ? "photo.fill.on.rectangle.fill" : "photo")
                                .font(.body)
                                .foregroundStyle(uploadedImageURL != nil ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isUploadingImage)
                    .accessibilityLabel("Attach photo")
                    PhotosPicker(selection: $selectedVideo, matching: .videos) {
                        if isUploadingVideo {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: uploadedVideoURL != nil ? "video.fill" : "video")
                                .font(.body)
                                .foregroundStyle(uploadedVideoURL != nil ? Color.accentColor : Color.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isUploadingVideo)
                    .accessibilityLabel("Attach video")
                    .onChange(of: selectedVideo) { _, newItem in
                        guard let newItem else { return }
                        Task { await uploadVideo(newItem) }
                    }
                    Button { } label: {
                        Text("M")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    Button { } label: {
                        Text("BS")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    Button { } label: {
                        Text("in")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    Button {
                        withAnimation {
                            showSchedulePicker.toggle()
                            if !showSchedulePicker { scheduledDate = nil }
                        }
                    } label: {
                        Image(systemName: scheduledDate != nil ? "calendar.badge.clock" : "calendar")
                            .font(.body)
                            .foregroundStyle(scheduledDate != nil ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(scheduledDate != nil ? "Clear schedule" : "Schedule post")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var schedulePicker: some View {
        DatePicker(
            "Send at",
            selection: Binding(
                get: { scheduledDate ?? Date().addingTimeInterval(3600) },
                set: { scheduledDate = $0 }
            ),
            in: Date()...,
            displayedComponents: [.date, .hourAndMinute]
        )
        .onAppear {
            if scheduledDate == nil {
                scheduledDate = Date().addingTimeInterval(3600)
            }
        }
        Button("Clear schedule") {
            scheduledDate = nil
            showSchedulePicker = false
        }
        .font(.caption)
        .foregroundStyle(.red)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func uploadedImagePreview(url: String) -> some View {
        HStack {
            if let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("Image attached")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                uploadedImageURL = nil
                selectedPhoto = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove attached image")
        }
    }

    @ViewBuilder
    private func uploadedVideoPreview(url: String) -> some View {
        HStack {
            Image(systemName: "video.fill")
                .foregroundStyle(.secondary)
            Text("Video attached")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                uploadedVideoURL = nil
                selectedVideo = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove attached video")
        }
    }

    private func uploadVideo(_ item: PhotosPickerItem) async {
        isUploadingVideo = true
        errorMessage = nil
        defer { isUploadingVideo = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
            uploadedVideoURL = try await APIClient.shared.uploadVideo(data: data, mimeType: mimeType)
        } catch APIError.status(403) {
            errorMessage = "Video upload requires an active subscription."
            selectedVideo = nil
        } catch {
            errorMessage = "Failed to upload video. Please try again."
            selectedVideo = nil
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        errorMessage = nil
        defer { isUploadingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            uploadedImageURL = try await APIClient.shared.uploadImage(data: data, mimeType: mimeType)
        } catch APIError.status(403) {
            errorMessage = "Image upload requires an active subscription."
            selectedPhoto = nil
        } catch {
            errorMessage = "Failed to upload image. Please try again."
            selectedPhoto = nil
        }
    }

    private func postMessage() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let isoScheduled = scheduledDate.map {
            ISO8601DateFormatter().string(from: $0)
        }
        let urls = uploadedImageURL.map { [$0] }
        let videoUrls = uploadedVideoURL.map { [$0] }
        do {
            _ = try await APIClient.shared.postMessage(
                content: text,
                publiclyVisible: publiclyVisible,
                parentId: replyTo?.id,
                tags: tagList.isEmpty ? nil : tagList,
                scheduledAt: isoScheduled,
                imageUrls: urls,
                videoUrls: videoUrls
            )
            showSuccess = true
            if isReply {
                dismiss()
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let message) {
            errorMessage = message
        } catch APIError.status(403) {
            errorMessage = "You may need to verify your email before posting."
        } catch {
            errorMessage = "Connection failed. Please try again."
        }
    }
}
