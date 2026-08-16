//
//  DMThreadView.swift
//  InterlinedList
//

import PhotosUI
import SwiftUI

struct DMThreadView: View {
    let username: String
    /// Pre-known user (from the inbox row / recipient picker) so the header can render
    /// before the thread loads. Optional because deep entry points may only have a username.
    var initialUser: DMUser?

    @EnvironmentObject private var authState: AuthState

    @State private var messages: [DMMessage] = []
    @State private var otherUser: DMUser?
    @State private var isMutual = true
    @State private var isBlocked = false
    @State private var isLoading = true
    @State private var loadError: String?

    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var attachmentURL: String?
    @State private var isUploadingImage = false

    @State private var pollTask: Task<Void, Never>?

    private var selfId: String? { authState.user?.id }
    private var recipientId: String? { otherUser?.id ?? initialUser?.id }
    private var canCompose: Bool { isMutual && !isBlocked }
    private var canAttach: Bool { authState.user?.emailVerified == true }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            composer
        }
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
        .onDisappear { pollTask?.cancel() }
    }

    private var headerTitle: String {
        (otherUser ?? initialUser)?.displayNameOrUsername ?? "@\(username)"
    }

    @ViewBuilder
    private var messageList: some View {
        if isLoading && messages.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, messages.isEmpty {
            ContentUnavailableView {
                Label("Unable to load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Retry") { Task { await initialLoad() } }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            DMBubble(message: message, isOutgoing: message.senderId == selfId)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        Divider()
        if !canCompose {
            Text(disabledReason)
                .font(.ilMono())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            VStack(spacing: 6) {
                if let attachmentURL, let url = URL(string: attachmentURL) {
                    HStack {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusMd))
                        Text("Image attached")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            self.attachmentURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Remove attached image")
                    }
                }
                if let sendError {
                    Text(sendError)
                        .font(.ilMono())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    if canAttach {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            if isUploadingImage {
                                ProgressView().frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "photo")
                                    .font(.system(size: 20))
                                    .foregroundStyle(ILColor.primary)
                            }
                        }
                        .disabled(isUploadingImage)
                        .accessibilityLabel("Attach image")
                    }
                    TextField("Message", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .accessibilityLabel("Message text")
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(canSend ? ILColor.primary : Color.secondary)
                        }
                    }
                    .disabled(!canSend || isSending)
                    .accessibilityLabel("Send message")
                }
            }
            .padding()
            .onChange(of: pickerItem) { _, item in
                if let item { Task { await uploadAttachment(item) } }
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentURL != nil
    }

    private var disabledReason: String {
        if isBlocked {
            return "You can't message this person."
        }
        return "You can only message people who follow you back."
    }

    // MARK: - Loading

    private func initialLoad() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let thread = try await APIClient.shared.dmThread(username: username)
            messages = thread.items
            otherUser = thread.otherUser
            isMutual = thread.isMutual
            isBlocked = thread.isBlocked
            startPolling()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            loadError = msg
        } catch {
            loadError = "Could not load this conversation."
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                await pollUpdates()
            }
        }
    }

    private func pollUpdates() async {
        guard let lastId = messages.last?.id else { return }
        do {
            let update = try await APIClient.shared.dmThreadUpdates(username: username, after: lastId)
            let known = Set(messages.map(\.id))
            let newOnes = update.items.filter { !known.contains($0.id) }
            if !newOnes.isEmpty {
                messages.append(contentsOf: newOnes)
            }
            isMutual = update.isMutual
            isBlocked = update.isBlocked
        } catch {
            // Polling is best-effort; ignore transient errors.
        }
    }

    // MARK: - Sending

    private func send() async {
        guard let recipientId else {
            sendError = "Could not resolve recipient."
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachmentURL.map { [$0] } ?? []
        guard !text.isEmpty || !attachments.isEmpty else { return }

        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            let sent = try await APIClient.shared.sendDirectMessage(recipientId: recipientId, body: text, imageUrls: attachments)
            messages.append(sent)
            draft = ""
            attachmentURL = nil
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.forbidden(let code) {
            // Authorization failures (`blocked`, `not_mutual`) come back as 403
            // with the code in the body; map them like validation codes.
            sendError = mappedSendError(code)
        } catch APIError.server(let code) {
            sendError = mappedSendError(code)
        } catch {
            sendError = "Message failed to send."
        }
    }

    private func mappedSendError(_ code: String) -> String {
        switch code {
        case "self_message": return "You can't message yourself."
        case "invalid_body": return "Message must be 1–10000 characters."
        case "invalid_images": return "One of the attached images is invalid."
        case "recipient_not_found": return "That person could not be found."
        case "blocked": return "You can't message this person."
        case "not_mutual": return "You can only message people who follow you back."
        default: return code
        }
    }

    // MARK: - Attachments

    private func uploadAttachment(_ item: PhotosPickerItem) async {
        isUploadingImage = true
        sendError = nil
        defer {
            isUploadingImage = false
            pickerItem = nil
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                sendError = "Could not read that image."
                return
            }
            guard let processed = ImageUploadProcessor.process(raw) else {
                sendError = "Could not process that image."
                return
            }
            attachmentURL = try await APIClient.shared.uploadDMImage(data: processed.data, mimeType: processed.mimeType)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            sendError = msg
        } catch {
            sendError = "Image upload failed."
        }
    }
}

/// A single chat bubble. Outgoing messages trail and tint; incoming lead and gray.
private struct DMBubble: View {
    let message: DMMessage
    let isOutgoing: Bool

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if !message.body.isEmpty {
                    MarkdownView(content: message.body)
                }
                ForEach(message.imageUrls, id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusMd))
                            case .empty:
                                ProgressView().frame(height: 120)
                            default:
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Attached image")
                    }
                }
            }
            .padding(10)
            .background(isOutgoing ? ILColor.primary.opacity(0.18) : ILColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusLg))
            if !isOutgoing { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isOutgoing ? "You" : "Them"): \(message.body)")
    }
}

#Preview {
    NavigationStack {
        DMThreadView(username: "testuser")
            .environmentObject(AuthState())
    }
}
