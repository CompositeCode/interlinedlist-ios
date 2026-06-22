# GAP-ENDPOINTS — Backend API Gaps

This document tracks backend API gaps required by the InterlinedList iOS app. The iOS `APIClient` (in `InterlinedList/Services/APIClient.swift`) **already issues these calls** with the exact request shape described below — when the backend ships an endpoint matching the contract, the iOS side lights up with no further client changes.

Each section is a **self-contained prompt** you can paste into the backend project's Claude Code session. The prompts assume the backend already has the documents/folders pattern at `/api/documents/folders` to mirror.

---

## How to use this document

1. Open a Claude Code session inside the `interlinedlist.com` backend repository.
2. Copy the entire fenced block under "Prompt" for the gap you want to close.
3. Paste it as your first message in that session.
4. The prompt is fully self-contained — it includes the route, request body, response shape, validation rules, and the rationale.

When a gap closes, delete the section from this doc and update `InterlinedListTests/APIClientTests/` if the live contract differs from the iOS expectation documented here.

---

## 1. List Folder CRUD — `GET/POST/PUT/DELETE /api/folders`

**Status:** High priority. Blocks PLAN-21 (List Schema Editor + folder tree UI). iOS `APIClient.listsAndFolders()` already calls `GET /api/folders` and silently swallows the 404; `createListFolder`, `updateListFolder`, and `deleteListFolder` are all wired up and waiting.

### Prompt

```
Implement List Folder CRUD at `/api/folders`. List folders organise the user's
lists in a tree (folders can nest), the same way document folders already work
at `/api/documents/folders` — copy that implementation as your starting point
and keep the patterns identical (auth, ownership checks, cascade rules, error
shape).

The InterlinedList iOS client already issues these requests with the exact
shapes below. Match them precisely so the iOS app picks up the feature with no
client changes.

### Endpoints

`GET /api/folders` — list every folder the authenticated user owns.
  Response 200:
    { "folders": [ { "id": "...", "name": "...", "parentId": "..."|null } ] }

`POST /api/folders` — create a folder.
  Request body (camelCase): { "name": "My Folder", "parentId": null }
  Response 201: { "folder": { "id": "...", "name": "...", "parentId": null } }
  Validation: name 1–80 chars; if parentId is non-null, it must reference a
  folder owned by the same user.

`PUT /api/folders/[id]` — rename and/or reparent.
  Request body: { "name"?: "New Name", "parentId"?: "id"|null }
  Response 200: { "folder": { ... updated ... } }
  Response 409 (duplicate name in the target parent):
    { "error": "A folder with that name already exists here" }
  Validation: reject reparenting under a descendant (cycle protection).

`DELETE /api/folders/[id]` — delete a folder.
  Response 200: { "message": "Folder deleted successfully" }
  Cascade: child lists move to root (folderId = null). Match whatever rule
  `/api/documents/folders/[id]` uses today and keep it consistent.

### Ownership and auth

All routes are Bearer-token authenticated. 401 on missing/invalid token, 403
when the folder belongs to another user, 404 when it does not exist.

### Tests

Mirror the existing `/api/documents/folders` test file. Cover: create at root,
create nested, rename, reparent, reject cycle, delete cascades child lists to
root, ownership 403, auth 401.
```

---

## 2. `PATCH /api/documents/[id]` — accept `folderId`

**Status:** Medium priority. iOS `APIClient.updateDocument(...)` already sends `folderId` in the PATCH body — the backend currently ignores it, so document moves silently no-op.

### Prompt

```
Extend `PATCH /api/documents/[id]` to accept a `folderId` field so the iOS
client can move a document between folders (or to root via null) without a
delete-and-recreate workaround.

The InterlinedList iOS client already sends this field in every document
update PATCH. The endpoint must accept (but not require) it.

### Change

Update the route handler at `app/api/documents/[id]/route.ts` (or equivalent
path in this codebase) to destructure `folderId` from the request body
alongside the existing `title`, `content`, `isPublic` fields, and persist it.

  const { title, content, isPublic, folderId } = body;
  // ...
  await prisma.document.update({
    where: { id: params.id },
    data: {
      ...(title !== undefined && { title }),
      ...(content !== undefined && { content }),
      ...(isPublic !== undefined && { isPublic: isPublic === true }),
      ...(folderId !== undefined && { folderId: folderId || null }),
    },
  });

### Validation

If `folderId` is non-null, verify it references a document folder owned by the
same user (return 403 otherwise). Treat empty string `""` as null.

### Tests

Add a test case to the existing PATCH suite: move to a folder, move to root
(folderId: null), reject move to another user's folder (403).
```

---

## 3. `GET /api/documents/search`

**Status:** Medium priority. iOS `APIClient.searchDocuments(q:limit:offset:)` already calls this endpoint and `APIClientSearchDocumentsTests.swift` asserts the shape below. Currently 404s in prod.

### Prompt

```
Implement document search at `GET /api/documents/search`. The InterlinedList
iOS client already calls this endpoint with the contract below, and the iOS
test suite asserts the response shape — match it exactly.

### Endpoint

`GET /api/documents/search?q={query}&limit={n}&offset={n}`

Query params:
  - q (required, 1–200 chars) — search string
  - limit (optional, default 20, max 100)
  - offset (optional, default 0)

Response 200:
  {
    "documents": [
      {
        "id": "...",
        "title": "...",
        "content": "...",        // include full content; iOS may render a snippet
        "folderId": "..."|null,
        "isPublic": true,
        "createdAt": "ISO8601",
        "updatedAt": "ISO8601"
      }
    ],
    "pagination": {
      "total": 42,
      "limit": 20,
      "offset": 0,
      "hasMore": true
    }
  }

### Implementation

Scope to the authenticated user's documents only. A simple case-insensitive
`title ILIKE '%q%' OR content ILIKE '%q%'` is sufficient for v1. Order by
`updatedAt DESC`. Postgres full-text (`tsvector`) can replace this later
without changing the contract.

### Validation and errors

  - 400 if q is missing, empty, or longer than 200 chars
  - 400 if limit > 100
  - 401 unauthenticated

### Tests

Cover: basic title match, basic content match, pagination (limit + offset),
empty q rejected, ownership scoping (user A's docs do not appear in user B's
search).
```

---

## 4. `GET /api/lists/search`

**Status:** Low priority. iOS `APIClient.searchLists(q:limit:offset:)` is wired but no iOS tests assert it yet, so the contract below is the source of truth.

### Prompt

```
Implement list search at `GET /api/lists/search`, mirroring the document
search endpoint exactly. The InterlinedList iOS client already calls this
with the contract below.

### Endpoint

`GET /api/lists/search?q={query}&limit={n}&offset={n}`

Query params:
  - q (required, 1–200 chars) — matched against title and description
  - limit (optional, default 20, max 100)
  - offset (optional, default 0)

Response 200:
  {
    "lists": [
      {
        "id": "...",
        "title": "...",
        "description": "..."|null,
        "isPublic": true,
        "folderId": "..."|null,
        "itemCount": 5,
        "createdAt": "ISO8601",
        "updatedAt": "ISO8601"
      }
    ],
    "pagination": { "total": 10, "limit": 20, "offset": 0, "hasMore": false }
  }

The list object shape should match what `GET /api/lists` returns today —
re-use the same DTO/serializer so any future field additions stay consistent.

### Implementation

Scope to the authenticated user's lists. Case-insensitive
`title ILIKE '%q%' OR description ILIKE '%q%'`. Order by `updatedAt DESC`.

### Validation and errors

Identical to /api/documents/search (see gap #3).

### Tests

Cover: title match, description match, null description handled, pagination,
ownership scoping.
```

---

## 5. `PUT /api/lists/[id]` — accept `isPublic`

**Status:** Low priority. iOS `APIClient.updateList(id:title:description:isPublic:)` already sends `isPublic` in the PUT body. Without backend support, visibility changes from the iOS schema editor require a full schema rebuild via `PUT /api/lists/[id]/schema`, which is destructive.

### Prompt

```
Extend `PUT /api/lists/[id]` to accept an `isPublic` field. Today this route
accepts `title`, `description`, `messageId`, `metadata`, `parentId`, but
ignores `isPublic`. The iOS client sends `isPublic` in every list metadata
update — the backend silently drops it.

### Change

Update the route handler at `app/api/lists/[id]/route.ts` (or equivalent) to
destructure and persist `isPublic`:

  const { title, description, messageId, metadata, parentId, isPublic } = body;
  // ...
  await prisma.list.update({
    where: { id: params.id },
    data: {
      ...(title !== undefined && { title }),
      ...(description !== undefined && { description }),
      ...(messageId !== undefined && { messageId }),
      ...(metadata !== undefined && { metadata }),
      ...(parentId !== undefined && { parentId: parentId || null }),
      ...(isPublic !== undefined && { isPublic: isPublic === true }),
    },
  });

### Tests

Add a case to the existing PUT suite: toggle isPublic true → false and back,
verify the schema DSL is not touched.
```

---

## Summary

| # | Endpoint / Change | Priority | iOS already calls it? |
|---|---|---|---|
| 1 | `GET/POST/PUT/DELETE /api/folders` | High | Yes — `listsAndFolders`, `createListFolder`, `updateListFolder`, `deleteListFolder` |
| 2 | `PATCH /api/documents/[id]` + `folderId` | Medium | Yes — `updateDocument` sends it today |
| 3 | `GET /api/documents/search` | Medium | Yes — `searchDocuments`, asserted by iOS tests |
| 4 | `GET /api/lists/search` | Low | Yes — `searchLists` (no iOS tests yet) |
| 5 | `PUT /api/lists/[id]` + `isPublic` | Low | Yes — `updateList` sends it today |
