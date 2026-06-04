# GAP-ENDPOINTS — Backend API Gaps

This document lists API endpoints that the iOS app requires but do not currently exist on the backend. Each section describes the feature, the expected contract, and which iOS plan depends on it.

---

## 1. List Folder CRUD

**Context:** The iOS app calls `GET /api/folders` (in `APIClient.listsAndFolders()`) to load list folders for the tree view. This route does not exist. The iOS app silently swallows the 404 and returns an empty folder list.

Document folders live under `/api/documents/folders` and are fully implemented. List folders need the same treatment under `/api/folders` (or `/api/lists/folders`).

**Required endpoints:**

### `GET /api/folders`
Returns all list folders for the authenticated user.
```json
{ "folders": [ { "id": "...", "name": "...", "parentId": "..." } ] }
```

### `POST /api/folders`
Creates a new list folder.

**Request:**
```json
{ "name": "My Folder", "parentId": null }
```
**Response (201):**
```json
{ "folder": { "id": "...", "name": "My Folder", "parentId": null } }
```

### `PUT /api/folders/[id]`
Renames or moves a folder.

**Request:** `{ "name"?: "New Name", "parentId"?: "parentFolderId" | null }`
**Response (200):** `{ "folder": { ... updated folder ... } }`
**Response (409):** `{ "error": "A folder with that name already exists here" }`

### `DELETE /api/folders/[id]`
Deletes a list folder. Should cascade: move all child lists to root (or hard-delete depending on product decision).

**Response (200):** `{ "message": "Folder deleted successfully" }`

**iOS Plan:** PLAN-21 (List Schema Editor notes this gap)

---

## 2. Move Document to a Different Folder

**Context:** `PUT /api/documents/[id]` currently only accepts `title`, `content`, and `isPublic`. There is no way to move a document to a different folder (or to root) after creation.

**Required change:** Add `folderId` to the `PUT /api/documents/[id]` request body.

### `PUT /api/documents/[id]` — extended
**Add to accepted fields:**
```json
{ "folderId": "targetFolderId" }   // or null to move to root
```

**Implementation note:** Validate that the target folder belongs to the same user.

**iOS Plan:** Future iOS plan for document move UI (post-PLAN-24). Document the gap now so the backend is ready.

---

## 3. Document Search

**Context:** No search endpoint exists for documents. Users currently have no way to find a document by title or content.

### `GET /api/documents/search`

**Query parameters:**
- `q` (required) — search string, matched against `title` and `content`
- `limit` (optional, default 20)
- `offset` (optional, default 0)

**Response (200):**
```json
{
  "documents": [
    { "id": "...", "title": "...", "folderId": "...", "updatedAt": "..." }
  ],
  "pagination": { "total": 42, "limit": 20, "offset": 0, "hasMore": true }
}
```

**Implementation note:** A simple `WHERE title ILIKE '%q%' OR content ILIKE '%q%'` query is sufficient for initial implementation. Full-text search (Postgres `tsvector`) can be added later.

**iOS Plan:** Future iOS plan for document search UI (post-PLAN-24).

---

## 4. List Search

**Context:** As the number of lists grows, users need to find lists by name. No search endpoint exists for lists.

### `GET /api/lists/search`

**Query parameters:**
- `q` (required) — matched against `title` and `description`
- `limit` (optional, default 20)
- `offset` (optional, default 0)

**Response (200):**
```json
{
  "lists": [
    { "id": "...", "title": "...", "isPublic": true, "itemCount": 5 }
  ],
  "pagination": { "total": 10, "limit": 20, "offset": 0, "hasMore": false }
}
```

**iOS Plan:** Future iOS plan for list search UI.

---

## 5. `PUT /api/lists/[id]` — Add `isPublic` field

**Context:** `PUT /api/lists/[id]` accepts `title`, `description`, `messageId`, `metadata`, `parentId` but **not** `isPublic`. Changing visibility currently requires going through `PUT /api/lists/[id]/schema` which replaces the entire schema.

For a simple metadata edit (rename/re-describe without touching columns), the iOS app should be able to update `isPublic` without rebuilding the DSL.

**Required change:** Add `isPublic` to the body of `PUT /api/lists/[id]`.

```typescript
const { title, description, messageId, metadata, parentId, isPublic } = body;
// ...
const updated = await prisma.list.update({
  where: { id: params.id },
  data: {
    // ... existing fields ...
    ...(isPublic !== undefined && { isPublic: isPublic === true }),
  },
  // ...
});
```

**iOS Plan:** PLAN-21 (List Schema Editor)

---

## Summary Table

| Endpoint | Status | Priority | iOS Plan |
|---|---|---|---|
| `GET /api/folders` | ❌ Missing | High | PLAN-21 |
| `POST /api/folders` | ❌ Missing | High | PLAN-21 |
| `PUT /api/folders/[id]` | ❌ Missing | Medium | PLAN-21 |
| `DELETE /api/folders/[id]` | ❌ Missing | Medium | PLAN-21 |
| `PUT /api/documents/[id]` + `folderId` | ❌ Missing field | Medium | Future |
| `GET /api/documents/search` | ❌ Missing | Medium | Future |
| `GET /api/lists/search` | ❌ Missing | Low | Future |
| `PUT /api/lists/[id]` + `isPublic` | ❌ Missing field | Low | PLAN-21 |
