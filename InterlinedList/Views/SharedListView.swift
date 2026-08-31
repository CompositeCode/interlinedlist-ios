//
//  SharedListView.swift
//  InterlinedList
//

import SwiftUI

/// Loader for a list share-link deep link
/// (`https://interlinedlist.com/lists/shared/<token>` / `interlinedlist://lists/shared/<token>`).
/// Resolves the token to a read-only list. Edit-capable links (`collaborator`/`manager`)
/// can't be *claimed* on iOS — the claim endpoint is session-cookie only — so we show the
/// rows read-only and offer a button to accept the invite on the web. The share token
/// grants no column schema, so rows are rendered generically from their `rowData`.
struct SharedListView: View {
    let token: String

    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var resolution: SharedListResolution?
    @State private var rows: [ListItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let resolution {
                    List {
                        if resolution.isEditLink {
                            Section { editLinkNotice }
                        }
                        if let description = resolution.list.description, !description.isEmpty {
                            Section { Text(description).foregroundStyle(.secondary) }
                        }
                        if rows.isEmpty {
                            ContentUnavailableView {
                                Label("No items", systemImage: "list.bullet")
                            } description: {
                                Text("This list has no items yet.")
                            }
                        } else {
                            Section {
                                ForEach(rows) { row in
                                    SharedListRow(item: row)
                                }
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView("Opening shared list…")
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
            .navigationTitle(resolution?.list.title ?? "Shared list")
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
                Text("This is an edit invite. Editing a shared list isn't available in the app yet — accept it on the web to start collaborating.")
                    .font(.ilMono())
            }
            .foregroundStyle(.secondary)
            if let url = ILWebURL.sharedList(token: token) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open on interlinedlist.com to accept", systemImage: "safari")
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            resolution = try await APIClient.shared.resolveSharedList(token: token)
            rows = (try? await APIClient.shared.sharedListData(token: token)) ?? []
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "This share link could not be opened."
        }
    }
}

/// A read-only row from a shared list. The share token grants no column schema, so the
/// row is rendered generically: a headline picked from the most useful `rowData` value,
/// with the remaining fields available on expansion.
private struct SharedListRow: View {
    let item: ListItem
    @State private var isExpanded = false

    private var headline: String {
        for key in ["title", "name", "subject", "summary"] {
            if let value = item.rowData[key]?.displayString, !value.isEmpty { return value }
        }
        if let first = item.rowData.sorted(by: { $0.key < $1.key }).first(where: { !$0.value.displayString.isEmpty }) {
            return first.value.displayString
        }
        return "—"
    }

    private var otherFields: [(key: String, value: String)] {
        item.rowData
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                let string = value.displayString
                return string.isEmpty ? nil : (key, string)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(headline).foregroundStyle(.primary)
                Spacer()
                if !otherFields.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.ilMono())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(otherFields, id: \.key) { field in
                        HStack(alignment: .top) {
                            Text(field.key).foregroundStyle(.secondary)
                            Spacer()
                            Text(field.value).multilineTextAlignment(.trailing)
                        }
                        .font(.ilBody(14))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SharedListView(token: "preview-token")
        .environmentObject(AuthState())
}
