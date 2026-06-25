# GAP-ENDPOINTS — API contracts that are under-documented

This file no longer tracks *missing* endpoints — as of 2026-06-25 the iOS
app consumes every endpoint family it needs, and the high/medium backend
gaps (B0/B2/B3/B5) are resolved and shipped. What remains is a list of
**contracts that are live but under-documented or ambiguous**, where the
iOS client had to guess a shape, decode defensively, or work around an
inconsistency.

Each item says: what's unclear, what the iOS client currently assumes,
and what documentation (or small contract change) would remove the guess.
Sources cross-checked this pass: `/api/openapi.json` (route-generated) and
the `/help/api/*` pages — which **disagree** in a few places noted below.

Last updated: 2026-06-25.

---

## A. Shape disagreements between OpenAPI and the help docs

### A1. `GET /api/users/{username}/lists/{id}` — two different documented shapes

- **OpenAPI** says: `{ "list": { id, title, parentId, children }, "ancestors": [...] }`.
- **`/help/api/public-profiles`** shows a **flat** object:
  `{ id, title, description, isPublic, schema, owner: { username, displayName }, createdAt }`.

These are mutually exclusive. The iOS client decodes **both** (tries a
nested `list` object, falls back to the flat object) to be safe.

**What would help:** publish the single canonical response, and confirm
whether it includes: `description`, `isPublic`, the `schema` DSL string,
a structured `properties` array, `owner`, `children`, and `ancestors`.
Right now a client can't know which fields to rely on.

### A2. `GET /api/users/{username}/lists/{id}/data` — row/pagination shape unspecified

- **OpenAPI**: response documented as no body.
- **help docs**: "same paginated row shape as the authenticated endpoint"
  but that shape isn't shown.

The iOS client assumes rows arrive under `rows` (falling back to `items`)
as `{ id, rowData, rowNumber, createdAt }`, with optional top-level
`properties` and a standard `pagination` block.

**What would help:** document the wrapping key (`rows` vs `items`), the
row object fields, whether `properties` (the schema) is included so a
read-only client can label columns, and the pagination shape.

### A3. `GET /api/users/{username}/lists` — no documented body

Neither source publishes the response. iOS assumes
`{ "lists": [ UserList ] }` (reusing the authenticated list shape, where
`title`→name and `parentId`→folderId). Please confirm the wrapping key
and the per-list fields (notably whether `itemCount`, `isPublic`, and
`description` are present for public lists).

---

## B. Endpoints documented as "no body" in OpenAPI (need response specs)

The OpenAPI generator emitted **no response schema** for several list
endpoints the iOS app now depends on. They work, but a client is guessing:

| Endpoint | iOS assumes | Confirm |
|---|---|---|
| `GET /api/organizations` | `{ organizations: [Organization], pagination? }` | wrapping key + per-item fields (esp. `userRole`, `memberCount`, `avatar`, `slug`) |
| `GET /api/user/organizations` | `{ organizations: [Organization] }` | same — does each item carry `userRole`? (see B1 below) |
| `GET /api/users/{username}/documents` | `{ documents: [...], folders: [...] }` ✅ (this one *is* in OpenAPI) | — |
| `PATCH /api/messages/{id}` | optionally returns `{ data: Message }` | does it return the updated message, or just 200? |

### B1. Org list items should carry `userRole` (saves a round-trip)

`GET /api/organizations/{id}` returns `userRole` (so the app knows whether
to show owner-only edit/delete), but `GET /api/user/organizations` and
`GET /api/organizations` don't document it. The iOS detail screen
currently **re-fetches** `GET /api/organizations/{id}` purely to learn the
caller's role. If the list endpoints included `userRole` + `memberCount`,
that extra request goes away.

---

## C. Watcher endpoints — small gaps that shaped the iOS design

### C1. `GET /api/lists/{id}/watchers/me` returns only `{ watching }` — no role

The roadmap wanted a "my role" badge on a shared list, but `/watchers/me`
only answers *whether* the caller watches the list, not their role
(watcher/collaborator/manager). There's no documented way for a
non-owner to learn their own role without `GET .../watchers` (which may be
manager-gated). As a result the iOS permission model is binary today:
**owner → full edit** (their own lists), **everyone else → read-only**
(public list view). Collaborator/manager editing of *someone else's* list
is deferred.

**What would help:** add `role` (and maybe `permissions`) to the
`/watchers/me` response.

### C2. `GET /api/lists/{id}/watchers/users` uses a non-standard pagination block

Everywhere else pagination is `{ total, limit, offset, hasMore }`. Here it
is `{ limit, offset, hasMore }` with `total` hoisted to a **sibling**
top-level field. This actually broke the iOS decoder once (it reused the
shared `Pagination` type, which requires `total`) and had to be special-
cased. Standardizing this block — or documenting the difference — would
prevent the trap.

### C3. `POST /api/lists/{id}/watchers` — self-watch semantics + return shape

- The body is `{ userId, role }` and the response is `{ watching: boolean }`
  (no created-watcher object / role echoed back).
- For the public "Watch this list" CTA the caller is adding **themselves**.
  iOS sends its own `userId` with `role: "watcher"`. It's unclear whether
  `userId` is required for self-watch or whether omitting it defaults to
  the authenticated user. Please document the self-watch path explicitly.

---

## D. Cross-posting & link metadata (Phase 4) — undocumented response detail

### D1. `POST /api/messages` cross-post result shape

The create response is documented as no body, but the message-compose UI
wants to tell the user "Posted to Bluesky ✓ · Mastodon ✗". iOS decodes an
**optional** `crossPostResults: [{ platform, success, error }]` and simply
shows nothing if it's absent. Please confirm whether the endpoint returns
per-platform results and, if so, the exact field names.

### D2. `linkedInTargets` value vocabulary

`POST /api/messages` accepts `linkedInTargets: [{ kind }]`. The valid
`kind` values aren't documented (`"personal"` / `"organization"`?), nor
whether an organization target needs an `organizationId`. iOS currently
only sends the simple `crossPostToLinkedIn` boolean and leaves targets
empty pending this.

### D3. Two different link-metadata shapes

- The **feed** message object exposes `linkMetadata.links[]` as
  `{ url, platform, metadata: { thumbnail, title, description, text, type }, fetchStatus }`.
- `POST /api/messages/{id}/metadata` returns
  `{ message, metadata: { links: [{ url, title, description, image }] } }`
  — a flatter, differently-named shape (`image` vs `metadata.thumbnail`).

iOS models both separately. One consistent link-preview schema across read
and refresh would be simpler for every client.

---

## E. Avatar endpoints don't return the updated user (carried over, low)

`POST /api/user/avatar/upload` and `/api/user/avatar/from-url` return only
`{ url }`. iOS issues a follow-up `GET /api/user` to refresh the avatar
everywhere. Returning the full updated `user` would drop that round-trip.

---

## F. Still genuinely missing / blocked (not just under-documented)

These remain real gaps blocking specific iOS features:

| Ref | Gap | Blocks |
|---|---|---|
| **B4** | `/api/github/*` requires a **session cookie** and rejects Bearer tokens. iOS is Bearer-only. | Phase 11 (GitHub integration) — deferred until Bearer auth or a `session-from-bearer` exchange exists. |
| **B6** | No tag discovery: `GET /api/tags/trending` / `GET /api/tags/autocomplete` don't exist. `?tag=` filtering works but has no discovery path. | Tag explorer + `#` autocomplete (the second half of Phase 13). |
| **B9** | `GET /api/follow/{userId}/status` for the caller's **own** id returns 200 but omits `following`/`followedBy`/`pendingRequest`. | Edge case only — iOS never queries self-status in production; flagged for contract correctness. |
| **B8** | No realtime (WebSocket/SSE) for feed/notifications; everything is pull-only. | Long-term; APNs (Phase 9) covers the highest-value push. |

---

## G. What iOS now consumes (for reference)

Every endpoint family below is wired and tested as of 2026-06-25:

auth (email/password + OAuth ×5, reset/verify, email change, delete
account) · user core + settings + avatar + identities + organizations ·
messages CRUD + **cross-post + repost + scheduled PATCH + search +
metadata** · image/video upload · lists CRUD + **structured schema** +
folders + connections + **watchers** · documents CRUD + folders + search +
**public reader** · **public browse (lists/docs)** · following +
**followers/following/mutuals/remove** · notifications tray +
**preferences** · exports.

Not consumed by design: Stripe/subscriptions (web-only — no in-app billing
UI), LinkedIn org integration, utility endpoints (location/weather/image
proxy), admin.
