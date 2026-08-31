//
//  SharedDocumentView.swift
//  InterlinedList
//

import SwiftUI

/// Loader for a document share-link deep link
/// (`https://interlinedlist.com/documents/shared/<token>`), G10. Resolves the token
/// to a read-only document. Edit-capable links (`collaborator`/`manager`) can't be
/// *claimed* on iOS — the claim endpoint is session-cookie only — so we show the
/// content read-only and point the user to the web to accept an edit invite.
struct SharedDocumentView: View {
    let token: String

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var resolution: SharedDocumentResolution?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let resolution {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if resolution.isEditLink {
                                editLinkNotice
                            }
                            Text(resolution.document.title)
                                .font(.ilDisplay(20))
                            if let content = resolution.document.content, !content.isEmpty {
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
                    ProgressView("Opening shared document…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Link unavailable", systemImage: "link.badge.plus")
                    } description: {
                        Text(errorMessage ?? "This share link is invalid, expired, or has been revoked.")
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(resolution?.document.title ?? "Shared document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var editLinkNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text("This is an edit invite. Editing a shared document isn't available in the app yet — accept it on the web to start collaborating.")
                    .font(.ilMono())
            }
            .foregroundStyle(.secondary)
            if let url = ILWebURL.sharedDocument(token: token) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open on interlinedlist.com to accept", systemImage: "safari")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ILColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            resolution = try await APIClient.shared.resolveSharedDocument(token: token)
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "This share link could not be opened."
        }
    }
}

#Preview {
    SharedDocumentView(token: "preview-token")
        .environmentObject(AuthState())
}
