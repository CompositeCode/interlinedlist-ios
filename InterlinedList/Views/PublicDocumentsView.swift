//
//  PublicDocumentsView.swift
//  InterlinedList
//

import SwiftUI

/// A read-only list of another user's public documents.
struct PublicDocumentsView: View {
    let username: String

    @EnvironmentObject private var authState: AuthState
    @State private var documents: [PublicDocumentSummary] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && documents.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, documents.isEmpty {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if documents.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "doc.text")
                } description: {
                    Text("@\(username) has no public documents.")
                }
            } else {
                List(documents) { doc in
                    NavigationLink {
                        PublicDocumentReader(documentId: doc.id, title: doc.title)
                            .environmentObject(authState)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.title).font(.body)
                            if let path = doc.relativePath, !path.isEmpty {
                                Text(path).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.publicDocuments(username: username)
            documents = response.documents
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load documents."
        }
    }
}

/// Read-only renderer for a single public document.
struct PublicDocumentReader: View {
    let documentId: String
    let title: String

    @EnvironmentObject private var authState: AuthState
    @State private var document: Document?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, 40)
            } else if let error {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(document?.title ?? title)
                        .font(.title2.bold())
                    if let content = document?.content, !content.isEmpty {
                        Text(content)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        Text("This document is empty.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .navigationTitle(document?.title ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            document = try await APIClient.shared.publicDocument(id: documentId)
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load this document."
        }
    }
}

#Preview {
    NavigationStack {
        PublicDocumentsView(username: "someone")
            .environmentObject(AuthState())
    }
}
