# Offline Document Sync — Design (G9)

**Status:** Proposal for review (2026-07-31). Nothing built yet.
**Scope:** Offline-capable **documents** (and document folders). Lists are **not**
covered — the `/api/documents/sync` endpoint is documents-only; lists have no
equivalent sync endpoint, so offline lists are out of scope here.

## 1. The backend contract (verified from source + live)

**Pull — `GET /api/documents/sync?lastSyncAt=<iso>`** (Bearer)
→ `{ folders: [...], documents: [...], lastSyncAt: <iso> }`.
- Delta since `lastSyncAt`; **full state** when the param is absent.
- Every folder/document row carries `createdAt`, `updatedAt`, and **`deletedAt`**
  (soft-delete tombstone) so deletions replicate.
- `lastSyncAt` in the response is the **new cursor** to persist for the next pull.
- Emits `RateLimit-*` headers (429 when exceeded) — must back off.

**Push — `POST /api/documents/sync`** (Bearer)
body `{ operations: [ { op: "create"|"update"|"delete", type: "folder"|"document", path, data } ] }`.
- Documents upsert **by client-supplied `id`** (`data:{ id, folderId, title, content, relativePath, isPublic }`); server recomputes `contentHash`.
- `delete` is a soft-delete (`deletedAt`).
- Folders resolve/create by `path`.
- **Last-writer-wins:** the update path overwrites server title/content with **no
  version guard** (unlike `PATCH /api/documents/:id`, which does guard). So the sync
  endpoint will not reject a stale write — conflict avoidance is the client's job.

This is the same contract the web `il-sync` CLI uses.

## 2. Design goals

1. **Instant, offline reads** — documents render from a local store immediately,
   with no network on the hot path; background delta-pull refreshes.
2. **Offline edits** — create/edit/delete while offline; changes queue and replay
   on reconnect.
3. **No silent data loss** — because the server is LWW, the client must *detect*
   divergence and never quietly clobber a server change the user hasn't seen.
4. **Incremental & flag-gated** — ship a safe read slice first; two-way behind a
   feature flag; never regress the current online-only document flow.

## 3. Proposed architecture

```
DocumentsView ─▶ DocumentStore (@MainActor ObservableObject)
                     │  in-memory folders+documents (source of truth for UI)
                     ├─▶ SyncCache (on-disk, per-user)   ← extends DataCache
                     │     • folders[], documents[] (with deletedAt)
                     │     • lastSyncAt cursor
                     │     • per-doc localState: .synced | .dirty | .deleted
                     │     • outbox: [SyncOperation]  (queued create/update/delete)
                     └─▶ DocumentSyncEngine (actor)
                           • pull(): GET /sync?lastSyncAt → merge deltas, advance cursor
                           • push(): drain outbox → POST /sync {operations}
                           • runs on: app foreground, DocumentsView appear, reconnect,
                             and after each local edit (debounced)
```

- **`DocumentStore`** replaces the ad-hoc `documents`/`documentFolders` slices in
  `AppDataStore` for the documents tab (or wraps them), so the UI binds to one
  offline-aware source.
- **`SyncCache`** builds on the existing `DataCache` (JSON under `Caches/ILDataCache/`),
  adding the cursor, per-doc state, and the outbox.
- **`DocumentSyncEngine`** is an `actor` (serialize pull/push; no overlapping syncs).
  Reachability via `NWPathMonitor`.

## 4. Sync algorithm (per cycle)

1. **Push first** (so local intent isn't overwritten by a concurrent pull merge):
   drain `outbox` → `POST /sync`. On success, mark those docs `.synced`, clear their
   ops. On failure/offline, keep the outbox.
2. **Pull:** `GET /sync?lastSyncAt=<cursor>`. For each returned row:
   - `deletedAt != nil` → remove locally (unless locally `.dirty` → conflict, §5).
   - else upsert into the store; if the local copy is `.dirty`, **conflict** (§5),
     otherwise overwrite and mark `.synced`.
3. Persist the new `lastSyncAt`. Debounce cycles; honor `RateLimit-*` / 429 backoff.

## 5. Conflict handling (the crux)

The server is LWW with no guard, so the client must decide. Baseline each local doc
with the `updatedAt` it was last synced at (`baseUpdatedAt`). A conflict = a doc is
locally `.dirty` **and** the pull returns a server `updatedAt` newer than
`baseUpdatedAt` (someone else changed it while we had unsynced edits).

**Recommended policy (default):** **last-writer-wins by push order, but never
destroy the loser** — on a detected conflict, keep the local edit as the live doc,
and preserve the server version as a **conflict copy** ("Title (conflicted copy
2026-07-31)") so nothing is lost; surface a one-line banner. This mirrors
Dropbox/Notes behavior and is safe without a real merge UI.

Alternatives (your call — see decision below): (a) **Prompt** on each conflict
(keep mine / keep theirs); (b) **pure LWW** (simplest, silent — not recommended
given data-loss risk); (c) **server-wins** for un-pushed dirties.

## 6. Slices (ship in this order, each independently valuable + flag-gated)

- **Slice 1 — Offline read + delta pull** *(Small–Medium, low risk).*
  Persist the full doc/folder set via `SyncCache`; render instantly from it; background
  `GET /sync` delta refresh with cursor; apply tombstones. Also adopt
  `GET /api/documents/tree` for the one-call hierarchy. **No write path, no conflict
  logic.** Immediate wins: offline reading + faster document tab. Can ship on its own.
- **Slice 2 — Offline edit queue + push** *(Medium).*
  Route create/edit/delete through the `outbox`; optimistic local apply; replay via
  `POST /sync` on reconnect; LWW. Feature-flagged.
- **Slice 3 — Conflict detection + resolution** *(Medium).*
  Baseline tracking + conflict-copy policy (§5) + banner. Only after Slices 1–2.

## 7. Testing

- `MockURLSession`: pull merge (adds/updates/tombstones), cursor advance, push
  operation-body shape (`operations[].{op,type,data}`), 429 backoff.
- `SyncCache`/engine unit tests: dirty/synced/deleted transitions, outbox drain,
  conflict detection (dirty + newer server `updatedAt` → conflict copy).
- No live network in tests; a manual E2E-style smoke against the test account
  (read-only pull only) to confirm the real `lastSyncAt`/tombstone shapes.

## 8. Risks / open questions

- **Lists are not covered** — no list sync endpoint; offline stays documents-only.
- **Inline images offline** — image upload needs network; queued docs referencing
  not-yet-uploaded images must defer or upload-on-reconnect. Slice 2+ concern.
- **Cache growth** — large document sets; consider a cap / LRU later.
- **`path`/`relativePath` semantics** on folder create ops — confirm against a live
  push before Slice 2 (no live writes done yet — would need an authorized write-test
  or the free/second account).
- **Interaction with `PATCH /api/documents/:id`** (the online edit path, which *does*
  version-guard) vs. the sync push (no guard) — Slice 2 should route document edits
  through **one** path (the sync outbox) when the flag is on, to avoid two writers.

## 9. Decision needed before building

1. **Conflict policy** — recommended: **conflict-copy** (keep both, never lose data).
   Alternatives: prompt / pure-LWW / server-wins.
2. **First slice to build** — recommended: **Slice 1 only** (offline read + delta
   pull), review, then decide on Slices 2–3.
