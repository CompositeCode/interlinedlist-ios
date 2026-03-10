//
//  ComposeView.swift
//  InterlinedList
//

import SwiftUI

/// Fallback when user's maxMessageLength is not available (matches API default).
private let defaultMaxMessageLength = 666

struct ComposeView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    /// When set, this view posts a reply to the given message.
    var replyTo: Message? = nil
    @State private var content = ""
    @State private var publiclyVisible = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showAdvancedBar = false

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
                                    Button { } label: {
                                        Image(systemName: "photo")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(true)
                                    Button { } label: {
                                        Image(systemName: "video.fill")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(true)
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
                                    Button { } label: {
                                        Image(systemName: "calendar")
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        Toggle("Public", isOn: $publiclyVisible)
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
                            Text(isReply ? "Reply" : "Post")
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
            .alert(isReply ? "Replied" : "Posted", isPresented: $showSuccess) {
                Button("OK") {
                    content = ""
                    applyUserDefaults()
                }
            } message: {
                Text(isReply ? "Your reply was posted." : "Your message was posted.")
            }
        }
    }

    private func postMessage() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            _ = try await APIClient.shared.postMessage(content: text, publiclyVisible: publiclyVisible, parentId: replyTo?.id)
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
