//
//  DocumentsView.swift
//  InterlinedList
//

import SwiftUI

struct DocumentsView: View {
    @EnvironmentObject var authState: AuthState
    @State private var allFolders: [DocumentFolder] = []
    @State private var allDocuments: [Document] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var showCreateFolder = false
    @State private var searchText = ""
    @State private var searchResults: [Document] = []
    @State private var isSearching = false

    private var rootFolders: [DocumentFolder] {
        allFolders.filter { ($0.parentId ?? "").isEmpty }
    }

    private var rootDocuments: [Document] {
        allDocuments.filter { ($0.folderId ?? "").isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !searchText.isEmpty {
                    searchResultsList
                } else if isLoading && allFolders.isEmpty && allDocuments.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if rootFolders.isEmpty && rootDocuments.isEmpty {
                    ContentUnavailableView {
                        Label("No Documents", systemImage: "doc.text")
                    } description: {
                        Text("Tap + to create your first document.")
                    }
                } else {
                    documentList
                }
            }
            .navigationTitle("Documents")
            .searchable(text: $searchText, prompt: "Search documents")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty { searchResults = [] }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: {
                            Label("New Document", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showCreateFolder = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New item")
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showCreate) {
                CreateDocumentView(folderId: nil) { newDoc in
                    allDocuments.insert(newDoc, at: 0)
                }
            }
            .sheet(isPresented: $showCreateFolder) {
                CreateDocumentFolderView(parentId: nil) { newFolder in
                    allFolders.append(newFolder)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(searchResults) { doc in
                NavigationLink(destination: DocumentDetailView(document: doc, onUpdate: { updated in
                    if let idx = allDocuments.firstIndex(where: { $0.id == updated.id }) {
                        allDocuments[idx] = updated
                    }
                }, onDelete: { id in
                    allDocuments.removeAll { $0.id == id }
                    searchResults.removeAll { $0.id == id }
                })) {
                    DocumentRow(document: doc)
                }
            }
        }
    }

    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let (results, _) = try await APIClient.shared.searchDocuments(q: q)
            searchResults = results
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch {
            searchResults = []
        }
    }

    private var documentList: some View {
        List {
            if !rootFolders.isEmpty {
                Section("Folders") {
                    ForEach(rootFolders) { folder in
                        NavigationLink(destination: DocumentFolderView(folder: folder)) {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                }
            }
            if !rootDocuments.isEmpty {
                Section("Documents") {
                    ForEach(rootDocuments) { doc in
                        NavigationLink(destination: DocumentDetailView(document: doc, onUpdate: { updated in
                            if let idx = allDocuments.firstIndex(where: { $0.id == updated.id }) {
                                allDocuments[idx] = updated
                            }
                        }, onDelete: { id in
                            allDocuments.removeAll { $0.id == id }
                        })) {
                            DocumentRow(document: doc)
                        }
                    }
                    .onDelete { offsets in
                        Task { await deleteDocuments(at: offsets, from: rootDocuments) }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let fTask = APIClient.shared.documentFolders()
            async let dTask = APIClient.shared.documents()
            let (f, d) = try await (fTask, dTask)
            allFolders = f
            allDocuments = d
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.status(403) {
            errorMessage = "Requires active subscription."
        } catch {
            errorMessage = "Failed to load documents."
        }
    }

    private func deleteDocuments(at offsets: IndexSet, from list: [Document]) async {
        let toDelete = offsets.map { list[$0] }
        allDocuments.removeAll { doc in toDelete.contains { $0.id == doc.id } }
        for doc in toDelete {
            try? await APIClient.shared.deleteDocument(id: doc.id)
        }
    }
}

private struct DocumentFolderView: View {
    let folder: DocumentFolder

    @EnvironmentObject var authState: AuthState
    @State private var subfolders: [DocumentFolder] = []
    @State private var documents: [Document] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var showCreateFolder = false

    var body: some View {
        Group {
            if isLoading && documents.isEmpty && subfolders.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                folderList
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showCreate = true
                    } label: {
                        Label("New Document", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showCreateFolder = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New item in \(folder.name)")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateDocumentView(folderId: folder.id) { newDoc in
                documents.insert(newDoc, at: 0)
            }
        }
        .sheet(isPresented: $showCreateFolder) {
            CreateDocumentFolderView(parentId: folder.id) { newFolder in
                subfolders.append(newFolder)
            }
        }
    }

    private var folderList: some View {
        List {
            if !subfolders.isEmpty {
                Section("Folders") {
                    ForEach(subfolders) { sub in
                        NavigationLink(destination: DocumentFolderView(folder: sub)) {
                            Label(sub.name, systemImage: "folder")
                        }
                    }
                }
            }
            Section("Documents") {
                ForEach(documents) { doc in
                    NavigationLink(destination: DocumentDetailView(document: doc, onUpdate: { updated in
                        if let idx = documents.firstIndex(where: { $0.id == updated.id }) {
                            documents[idx] = updated
                        }
                    }, onDelete: { id in
                        documents.removeAll { $0.id == id }
                    })) {
                        DocumentRow(document: doc)
                    }
                }
                .onDelete { offsets in
                    Task { await deleteDocuments(at: offsets) }
                }
                if documents.isEmpty && !isLoading {
                    Text("No documents in this folder.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fTask = APIClient.shared.documentFolders()
            async let dTask = APIClient.shared.documents(folderId: folder.id)
            let (allFolders, docs) = try await (fTask, dTask)
            subfolders = allFolders.filter { $0.parentId == folder.id }
            documents = docs
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch { }
    }

    private func deleteDocuments(at offsets: IndexSet) async {
        let toDelete = offsets.map { documents[$0] }
        documents.remove(atOffsets: offsets)
        for doc in toDelete {
            try? await APIClient.shared.deleteDocument(id: doc.id)
        }
    }
}

private struct DocumentRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.title)
                .font(.body)
            if let updatedAt = document.updatedAt, let date = parseISODate(updatedAt) {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DocumentDetailView: View {
    let document: Document
    var onUpdate: (Document) -> Void
    var onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var current: Document
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    init(document: Document, onUpdate: @escaping (Document) -> Void, onDelete: @escaping (String) -> Void) {
        self.document = document
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _current = State(initialValue: document)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let content = current.content, !content.isEmpty {
                    if let attributed = try? AttributedString(markdown: content,
                        options: .init(interpretedSyntax: .full)) {
                        Text(attributed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("No content")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .padding()
        }
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showEdit = true }
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            EditDocumentView(document: current) { updated in
                current = updated
                onUpdate(updated)
            }
        }
        .confirmationDialog("Delete \"\(current.title)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await APIClient.shared.deleteDocument(id: current.id)
                    onDelete(current.id)
                    dismiss()
                }
            }
        }
    }
}

private struct CreateDocumentView: View {
    let folderId: String?
    var onSave: (Document) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var title = ""
    @State private var content = ""
    @State private var isPublic = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Document title", text: $title)
                }
                Section("Content (Markdown)") {
                    TextField("Write in markdown…", text: $content, axis: .vertical)
                        .lineLimit(8...20)
                        .font(.system(.body, design: .monospaced))
                }
                Section {
                    Toggle("Public", isOn: $isPublic)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let doc = try await APIClient.shared.createDocument(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.isEmpty ? nil : content,
                isPublic: isPublic,
                folderId: folderId
            )
            onSave(doc)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.status(403) {
            errorMessage = "Requires active subscription."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to create document."
        }
    }
}

private struct EditDocumentView: View {
    let document: Document
    var onSave: (Document) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @State private var title: String
    @State private var content: String
    @State private var isPublic: Bool
    @State private var selectedFolderId: String?
    @State private var availableFolders: [DocumentFolder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(document: Document, onSave: @escaping (Document) -> Void) {
        self.document = document
        self.onSave = onSave
        _title = State(initialValue: document.title)
        _content = State(initialValue: document.content ?? "")
        _isPublic = State(initialValue: document.isPublic ?? false)
        let fid = document.folderId ?? ""
        _selectedFolderId = State(initialValue: fid.isEmpty ? nil : fid)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Document title", text: $title)
                }
                Section("Content (Markdown)") {
                    TextField("Write in markdown…", text: $content, axis: .vertical)
                        .lineLimit(8...20)
                        .font(.system(.body, design: .monospaced))
                }
                Section {
                    Toggle("Public", isOn: $isPublic)
                }
                Section("Location") {
                    Picker("Folder", selection: $selectedFolderId) {
                        Text("No Folder").tag(String?.none)
                        ForEach(availableFolders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .task {
                if let folders = try? await APIClient.shared.documentFolders() {
                    availableFolders = folders
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let folderIdToSend: String? = selectedFolderId.flatMap { $0.isEmpty ? nil : $0 }
            let updated = try await APIClient.shared.updateDocument(
                id: document.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: content.isEmpty ? nil : content,
                isPublic: isPublic,
                folderId: folderIdToSend
            )
            onSave(updated)
            dismiss()
        } catch APIError.status(401) {
            authState.handleUnauthorized()
        } catch APIError.status(403) {
            errorMessage = "Requires active subscription."
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to save changes."
        }
    }
}

private struct CreateDocumentFolderView: View {
    let parentId: String?
    var onSave: (DocumentFolder) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Name", text: $name)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let folder = try await APIClient.shared.createDocumentFolder(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                parentId: parentId
            )
            onSave(folder)
            dismiss()
        } catch APIError.server(let msg) {
            errorMessage = msg
        } catch {
            errorMessage = "Failed to create folder."
        }
    }
}

private func parseISODate(_ string: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: string) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: string)
}

#Preview {
    DocumentsView()
        .environmentObject(AuthState())
}
