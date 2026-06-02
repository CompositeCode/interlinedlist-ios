# Plan 18 — Data Exports

## Status
Endpoints marked "Needs Bearer" — test first; they may already accept Bearer tokens.

## Goal
Add export actions to `ProfileView` (or `EditProfileView`) that download CSV data and present iOS's native share sheet via `ShareLink`.

## Endpoints

| Method | Path | Returns |
|--------|------|---------|
| GET | `/api/exports/messages` | CSV of user's messages |
| GET | `/api/exports/lists` | CSV of user's lists |
| GET | `/api/exports/follows` | CSV of user's follow relationships |

## Files to Change

| File | Change |
|------|--------|
| `InterlinedList/Services/APIClient.swift` | Add `exportCSV(type:)` method |
| `InterlinedList/Views/UserProfileView.swift` | Add exports section (own profile only) |

## Step-by-Step

### 1. `APIClient.swift` — add raw-data GET helper + export methods

The existing `get<T: Decodable>` returns decoded JSON. Exports return CSV bytes. Add a raw-data variant:

```swift
private func getRawData(_ path: String) async throws -> Data {
    guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await session.data(for: request)
    try checkResponse(data: data, response: response)
    return data
}
```

Add export methods:

```swift
enum ExportType: String {
    case messages, lists, follows
}

func exportCSV(_ type: ExportType) async throws -> Data {
    return try await getRawData("/api/exports/\(type.rawValue)")
}
```

### 2. `Views/UserProfileView.swift` — add exports section (own profile)

Exports only make sense on the authenticated user's own profile. Find the condition that checks whether the viewed profile is the current user (e.g. `viewedUsername == authState.user?.username`) and gate the section there.

**New state vars:**
```swift
@State private var isExporting: ExportType? = nil
@State private var exportedData: Data? = nil
@State private var exportFilename: String = "export.csv"
@State private var showShareSheet = false
@State private var exportError: String? = nil
```

**Add an "Exports" section** at the bottom of the profile form/list:

```swift
Section("Export Your Data") {
    exportButton(label: "Messages", type: .messages)
    exportButton(label: "Lists", type: .lists)
    exportButton(label: "Follows", type: .follows)
    if let err = exportError {
        Text(err).foregroundStyle(.red).font(.caption)
    }
}
```

**`exportButton` helper view:**

```swift
@ViewBuilder
private func exportButton(label: String, type: ExportType) -> some View {
    Button {
        Task { await export(type) }
    } label: {
        HStack {
            if isExporting == type {
                ProgressView().frame(width: 20, height: 20)
            }
            Text("Export \(label) (CSV)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.secondary)
        }
    }
    .disabled(isExporting != nil)
}
```

**`export` function:**

```swift
private func export(_ type: ExportType) async {
    exportError = nil
    isExporting = type
    defer { isExporting = nil }
    do {
        let data = try await APIClient.shared.exportCSV(type)
        exportedData = data
        exportFilename = "\(type.rawValue)-export.csv"
        showShareSheet = true
    } catch APIError.status(401) {
        authState.handleUnauthorized()
    } catch APIError.server(let msg) {
        exportError = msg
    } catch {
        exportError = "Export failed. Please try again."
    }
}
```

**Wire share sheet:**

Use `.sheet(isPresented: $showShareSheet)` presenting a `ShareSheet` wrapper:

```swift
.sheet(isPresented: $showShareSheet) {
    if let data = exportedData {
        ShareSheet(items: [data], filename: exportFilename)
    }
}
```

**`ShareSheet` UIViewControllerRepresentable:**

```swift
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let filename: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Write data to a temp file so the share sheet can offer "Save to Files"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if let data = items.first as? Data { try? data.write(to: url) }
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

Using a temp file (rather than raw `Data`) ensures the share sheet shows the filename and allows "Save to Files".

## Acceptance Criteria
- Export section only visible when viewing own profile.
- Tapping each export button shows a spinner, then opens the iOS share sheet.
- Share sheet offers the file with the correct name (e.g. `messages-export.csv`).
- 401 triggers logout. Server errors show inline in red.
- Build succeeds.
