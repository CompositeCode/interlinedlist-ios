//
//  DocumentLinkView.swift
//  InterlinedList
//

import SwiftUI

/// Loader shown when a `interlinedlist://documents/<id>` (or web permalink) deep
/// link opens (G10). A permalink only carries the document id, so this fetches the
/// document and presents loading / error / loaded states, mirroring `MessageLinkView`.
struct DocumentLinkView: View {
    let documentId: String

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var document: Document?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(document.title)
                                .font(.ilDisplay(20))
                            if let content = document.content, !content.isEmpty {
                                MarkdownView(content: content)
                                    .textSelection(.enabled)
                            } else {
                                Text("This document is empty.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                } else if isLoading {
                    ProgressView("Loading document…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Unable to open document", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "This document could not be loaded.")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(document?.title ?? "Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            document = try await APIClient.shared.publicDocument(id: documentId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
            errorMessage = "You need to be signed in to view this document."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "This document could not be loaded."
        }
    }
}

#Preview {
    DocumentLinkView(documentId: "preview-id")
        .environmentObject(AuthState())
}
