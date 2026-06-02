# Plan 19 — List Connections

## Status
Endpoints marked "Needs Bearer" — test first with existing Bearer token before assuming server work is needed.

## Goal
Add a "Connections" section to `ListDetailView` (inside `ListsView.swift`) that shows which other lists this list is connected to, and allows adding/removing connections.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/lists/connections` | All connections for the authenticated user |
| POST | `/api/lists/connections` | Create a connection between two lists |
| DELETE | `/api/lists/connections/[id]` | Remove a connection |

Expected POST body (inferred from API docs):
```json
{ "sourceListId": "...", "targetListId": "..." }
```

Expected GET response:
```json
{
  "connections": [
    { "id": "...", "sourceListId": "...", "targetListId": "...", "createdAt": "..." }
  ]
}
```

## Files to Change

| File | Change |
|------|--------|
| `InterlinedList/Models/List.swift` | Add `ListConnection` model |
| `InterlinedList/Services/APIClient.swift` | Add connection methods |
| `InterlinedList/Views/ListsView.swift` | Add connections section to `ListDetailView` |

## Step-by-Step

### 1. `Models/List.swift` — add `ListConnection`

```swift
struct ListConnection: Identifiable, Codable {
    let id: String
    let sourceListId: String
    let targetListId: String
    let createdAt: String?
}
```

Add response wrapper alongside existing ones at the bottom of the file:

```swift
struct ConnectionsResponse: Decodable {
    let connections: [ListConnection]
}
```

### 2. `APIClient.swift` — add MARK: List Connections section

```swift
// MARK: - List Connections

func listConnections() async throws -> [ListConnection] {
    let response: ConnectionsResponse = try await get("/api/lists/connections")
    return response.connections
}

func createListConnection(sourceListId: String, targetListId: String) async throws -> ListConnection {
    struct Body: Encodable { let sourceListId: String; let targetListId: String }
    struct R: Decodable { let connection: ListConnection? }
    let r: R = try await postCamel("/api/lists/connections",
                                    body: Body(sourceListId: sourceListId, targetListId: targetListId))
    guard let conn = r.connection else { throw APIError.noData }
    return conn
}

func deleteListConnection(id: String) async throws {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    guard let url = URL(string: baseURL + "/api/lists/connections/\(enc)") else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await session.data(for: request)
    try checkResponse(data: data, response: response)
}
```

Note: `postCamel` used because `sourceListId`/`targetListId` are camelCase keys — the server likely expects them as-is.

### 3. `ListsView.swift` — add connections section to `ListDetailView`

Locate `ListDetailView` (the view shown when a user taps a list). Add new state:

```swift
@State private var connections: [ListConnection] = []
@State private var allLists: [UserList] = []
@State private var showAddConnection = false
@State private var connectionsError: String? = nil
```

**Load connections** in the existing `.task {}` block (alongside list items):

```swift
async let connectionsResult = APIClient.shared.listConnections()
async let allListsResult = APIClient.shared.listsAndFolders()
// ... existing item load ...
do {
    connections = (try? await connectionsResult)?
        .filter { $0.sourceListId == list.id || $0.targetListId == list.id } ?? []
    allLists = (try? await allListsResult)?.lists ?? []
} 
```

**Add `ConnectionsSection`** at the bottom of the `ListDetailView` body:

```swift
Section {
    if connections.isEmpty {
        Text("No connections yet")
            .foregroundStyle(.secondary)
            .font(.subheadline)
    } else {
        ForEach(connections) { conn in
            let otherListId = conn.sourceListId == list.id ? conn.targetListId : conn.sourceListId
            let otherList = allLists.first { $0.id == otherListId }
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                Text(otherList?.name ?? otherListId)
            }
        }
        .onDelete { indexSet in
            Task {
                for index in indexSet {
                    let conn = connections[index]
                    try? await APIClient.shared.deleteListConnection(id: conn.id)
                    connections.remove(at: index)
                }
            }
        }
    }
} header: {
    HStack {
        Text("Connections")
        Spacer()
        Button {
            showAddConnection = true
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Add connection")
    }
}
```

**Add connection picker sheet** — a simple list of other lists the user can connect to:

```swift
.sheet(isPresented: $showAddConnection) {
    NavigationStack {
        List {
            ForEach(allLists.filter { $0.id != list.id }) { candidate in
                Button(candidate.name) {
                    Task {
                        if let conn = try? await APIClient.shared.createListConnection(
                            sourceListId: list.id,
                            targetListId: candidate.id
                        ) {
                            connections.append(conn)
                        }
                        showAddConnection = false
                    }
                }
            }
        }
        .navigationTitle("Connect to List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showAddConnection = false }
            }
        }
    }
}
```

## Acceptance Criteria
- "Connections" section visible at the bottom of `ListDetailView`.
- Tapping "+" opens a picker of other lists to connect to.
- Selecting a list creates the connection and it appears in the section.
- Swipe-to-delete removes the connection from the server.
- Lists that are already connected to this list are excluded from the picker (optional stretch goal).
- 401 from any connection endpoint triggers `authState.handleUnauthorized()`.
- Build succeeds.
