//
//  PublicListDetailView.swift
//  InterlinedList
//

import SwiftUI

/// Read-only view of another user's public list, with a Watch / Unwatch CTA.
struct PublicListDetailView: View {
    let username: String
    let listId: String
    var listTitle: String?

    @EnvironmentObject private var authState: AuthState
    @State private var detail: PublicListDetail?
    @State private var rows: [ListItem] = []
    @State private var properties: [ListPropertyDef] = []
    @State private var isLoading = true
    @State private var error: String?

    @State private var isWatching: Bool?
    @State private var isWatchLoading = false
    @State private var watchError: String?

    var body: some View {
        Group {
            if isLoading && rows.isEmpty && detail == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, detail == nil {
                ContentUnavailableView {
                    Label("Unable to load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else {
                listBody
            }
        }
        .navigationTitle(detail?.title ?? listTitle ?? "List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                watchButton
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var listBody: some View {
        List {
            if let desc = detail?.description, !desc.isEmpty {
                Section {
                    Text(desc).font(.ilBody(15)).foregroundStyle(.secondary)
                }
            }
            if let watchError {
                Section { Text(watchError).font(.ilMono()).foregroundStyle(.red) }
            }
            if let children = detail?.children, !children.isEmpty {
                Section("Sub-lists") {
                    ForEach(children) { child in
                        NavigationLink {
                            PublicListDetailView(username: username, listId: child.id, listTitle: child.title)
                                .environmentObject(authState)
                        } label: {
                            Label(child.title ?? "Untitled", systemImage: "list.bullet.indent")
                        }
                    }
                }
            }
            Section(rows.isEmpty ? "" : "Items") {
                if rows.isEmpty {
                    Text("This list has no items.")
                        .foregroundStyle(.secondary)
                        .font(.ilBody(15))
                } else {
                    ForEach(rows) { row in
                        PublicListRow(row: row, properties: orderedProperties)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Visible properties in display order; falls back to whatever the data call returned.
    private var orderedProperties: [ListPropertyDef] {
        let source = properties.isEmpty ? (detail?.properties ?? []) : properties
        return source.filter { $0.isVisible }.sorted { $0.displayOrder < $1.displayOrder }
    }

    @ViewBuilder
    private var watchButton: some View {
        if isWatchLoading {
            ProgressView()
        } else if let watching = isWatching {
            Button {
                Task { await toggleWatch() }
            } label: {
                Label(watching ? "Watching" : "Watch",
                      systemImage: watching ? "eye.fill" : "eye")
            }
            .accessibilityLabel(watching ? "Stop watching this list" : "Watch this list")
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let detailTask = APIClient.shared.publicListDetail(username: username, listId: listId)
            async let dataTask = APIClient.shared.publicListData(username: username, listId: listId)
            let (d, data) = try await (detailTask, dataTask)
            detail = d
            rows = data.rows
            properties = data.properties ?? d.properties ?? []
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            self.error = "Could not load this list."
        }
        // Watch status is best-effort and independent of the list body.
        isWatching = try? await APIClient.shared.isWatchingList(listId: listId)
    }

    private func toggleWatch() async {
        guard let userId = authState.user?.id, let watching = isWatching else { return }
        isWatchLoading = true
        watchError = nil
        defer { isWatchLoading = false }
        do {
            if watching {
                try await APIClient.shared.removeWatcher(listId: listId, userId: userId)
                isWatching = false
            } else {
                _ = try await APIClient.shared.addWatcher(listId: listId, userId: userId, role: .watcher)
                isWatching = true
            }
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.server(let msg) {
            watchError = msg
        } catch {
            watchError = "Could not update watch status."
        }
    }
}

/// One read-only data row rendered as labelled key/value pairs.
private struct PublicListRow: View {
    let row: ListItem
    let properties: [ListPropertyDef]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(pairs, id: \.label) { pair in
                HStack(alignment: .top, spacing: 8) {
                    Text(pair.label)
                        .font(.ilMono())
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(pair.value)
                        .font(.ilBody(15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Build ordered (label, value) pairs. When schema properties are known, use
    /// them for labels and order; otherwise fall back to the raw row keys.
    private var pairs: [(label: String, value: String)] {
        if !properties.isEmpty {
            return properties.compactMap { prop in
                guard let value = row.rowData[prop.propertyKey], value != .null else { return nil }
                let display = value.displayString
                guard !display.isEmpty else { return nil }
                return (prop.propertyName, display)
            }
        }
        return row.rowData
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                let display = value.displayString
                guard !display.isEmpty else { return nil }
                return (key, display)
            }
    }
}

#Preview {
    NavigationStack {
        PublicListDetailView(username: "someone", listId: "list-1", listTitle: "Books")
            .environmentObject(AuthState())
    }
}
