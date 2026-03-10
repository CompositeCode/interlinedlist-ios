//
//  ComposeView.swift
//  InterlinedList
//

import SwiftUI

struct ComposeView: View {
    @EnvironmentObject var authState: AuthState
    @State private var content = ""
    @State private var publiclyVisible = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $content, axis: .vertical)
                        .lineLimit(5...15)
                    Toggle("Public", isOn: $publiclyVisible)
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
                            Text("Post")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Posted", isPresented: $showSuccess) {
                Button("OK") {
                    content = ""
                }
            } message: {
                Text("Your message was posted.")
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
            _ = try await APIClient.shared.postMessage(content: text, publiclyVisible: publiclyVisible)
            showSuccess = true
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
