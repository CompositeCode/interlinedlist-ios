# PLAN-23: Fix Document Loading Bugs & Add Folder Management

## Bugs to Fix

Three silent bugs exist in the current document implementation, discovered by reading the backend source.

---

### Bug 1: `updateDocument` sends PATCH; backend only has PUT

**Location:** `APIClient.updateDocument` (`APIClient.swift:286`)

```swift
// CURRENT — wrong HTTP method
let response: Response = try await patch("/api/documents/\(encoded)", ...)
```

The backend route file `app/api/documents/[id]/route.ts` exports `PUT` only — there is no `PATCH` handler. Every edit save silently receives a 405 (Method Not Allowed) or falls through without updating.

**Fix:** Change `patch(...)` to `put(...)`.

---

### Bug 2: `documents(folderId:)` fetches from the wrong endpoint

**Location:** `APIClient.documents(folderId:)` (`APIClient.swift:264`)

```swift
// CURRENT — appends ?folderId= query that GET /api/documents ignores
var path = "/api/documents"
if let folderId, !folderId.isEmpty { path += "?folderId=\(encoded)" }
```

`GET /api/documents` returns only root-level documents (`WHERE folderId IS NULL`). It ignores any query parameters. Documents inside a folder must be fetched from `GET /api/documents/folders/[id]/documents`.

**Fix:** When `folderId` is non-nil, call `GET /api/documents/folders/[folderId]/documents` instead.

---

### Bug 3: `createDocument(folderId:)` always creates at root

**Location:** `APIClient.createDocument` (`APIClient.swift:274`)

```swift
// CURRENT — always POSTs to root endpoint regardless of folderId param
let response: Response = try await post("/api/documents", ...)
```

`POST /api/documents` creates a root document (`folderId: null`). Creating a document inside a folder requires `POST /api/documents/folders/[id]/documents`.

**Fix:** When `folderId` is non-nil, POST to `/api/documents/folders/[folderId]/documents`.

---

## New Feature: Document Folder Rename & Delete

The backend already has:
- `PUT /api/documents/folders/[id]` — rename or move folder (`{ name?, parentId? }`)
- `DELETE /api/documents/folders/[id]` — soft-deletes folder and all its contents

The iOS app has no UI or API client methods for either.

### New `APIClient` methods

```swift
func updateDocumentFolder(id: String, name: String) async throws -> DocumentFolder
func deleteDocumentFolder(id: String) async throws
```

`updateDocumentFolder` sends `PUT /api/documents/folders/[id]` with `{ "name": "..." }`.
`deleteDocumentFolder` sends `DELETE /api/documents/folders/[id]`.

### `DocumentFolderView` changes

Add a toolbar menu (ellipsis icon) with:
- **Rename** — shows an alert with a text field pre-filled with the current folder name. Calls `updateDocumentFolder`.
- **Delete Folder** — shows a `confirmationDialog` warning that all contents will be deleted. Calls `deleteDocumentFolder`, then pops the navigation stack.

## API Response Reference

### `PUT /api/documents/folders/[id]`
```json
{ "message": "Folder updated successfully", "folder": { "id": "...", "name": "...", ... } }
```

### `DELETE /api/documents/folders/[id]`
```json
{ "message": "Folder deleted successfully" }
```

409 Conflict: `{ "error": "A folder with that name already exists here" }` — surface inline.

## Files to Modify / Create

| File | Action |
|---|---|
| `InterlinedList/Services/APIClient.swift` | Fix `updateDocument` (patch→put), fix `documents(folderId:)` endpoint, fix `createDocument(folderId:)` endpoint, add `updateDocumentFolder`, `deleteDocumentFolder` |
| `InterlinedList/Views/DocumentsView.swift` | Add rename/delete menu to `DocumentFolderView` |

## Unit Tests

**`APIClientDocumentsTests.swift`** — add/update:
- `test_updateDocument_sendsPutNotPatch`
- `test_documents_withFolderId_usesCorrectPath` — asserts path is `/api/documents/folders/[id]/documents`
- `test_createDocument_withFolderId_postsToFolderPath`
- `test_updateDocumentFolder_sendsPutWithName`
- `test_deleteDocumentFolder_sendsDeleteToCorrectPath`

## Acceptance Criteria
- [ ] Editing a document and tapping Save successfully updates it (was silently failing)
- [ ] Opening a document folder shows the documents in that folder, not root documents
- [ ] Creating a document while inside a folder places it in that folder
- [ ] Folder rename: toolbar → Rename → type new name → confirm → folder header updates
- [ ] Folder delete: toolbar → Delete Folder → confirm → navigate back, folder gone from list
- [ ] Conflict on rename (duplicate name) shows error inline
