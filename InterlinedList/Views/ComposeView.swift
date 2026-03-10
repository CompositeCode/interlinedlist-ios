//
//  ComposeView.swift
//  InterlinedList
//

import SwiftUI

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

    private var isReply: Bool { replyTo != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isReply ? "Write a reply…" : "What's on your mind?", text: $content, axis: .vertical)
                        .lineLimit(5...15)
                    if !isReply {
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
            .alert(isReply ? "Replied" : "Posted", isPresented: $showSuccess) {
                Button("OK") {
                    content = ""
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
