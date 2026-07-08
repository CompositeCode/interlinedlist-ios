# Blocker Prompts — InterlinedList API

Actionable prompts for the backend team (or an AI coding assistant) describing
what the server needs to build or fix to unblock iOS App Store submission and v1
feature completion. Ordered by urgency:

- **Hard blockers** — App Store submission fails without these
- **v1 targets** — should ship with the first release
- **Quality improvements** — not blockers; fix before v1 if possible
- **Deferred** — post-v1; documented so the contracts are recorded

Cross-references: `App-Store-Deployment.md` for the iOS-side feature phases;
the API openapi.json and `/help/api/*` pages for current route definitions.

---

## Audit log

| Date | Summary |
|---|---|
| 2026-07-02 | Initial audit. All items below identified as outstanding. |
| 2026-07-07 | Re-audit. All hard blockers and v1 targets confirmed resolved. One new Bearer-auth gap found on `GET /api/user/organizations`. See Prompt 8 (updated). |

---

## HARD BLOCKERS

### 1. Implement content reporting endpoints ✅ RESOLVED 2026-07-07

**Why:** Apple Guideline 1.2 requires every UGC/social app to let users
report objectionable content. The iOS app **will be rejected** without this.
Phase 14 in `App-Store-Deployment.md`.

**Build:**

`POST /api/messages/{id}/report`
```
Request (camelCase JSON, Bearer auth):
{
  "reason": "spam" | "harassment" | "misinformation" | "inappropriate" | "other",
  "detail": "optional free-text string"
}

Response 200:
{ "reported": true }
```
- Idempotent — a second report from the same user on the same message returns 200, not 409
- Store reports server-side for moderation review (even if there's no moderation UI yet)

`POST /api/users/{id}/report`
```
Request: same shape as message report
Response: { "reported": true }
```
- `{id}` is the user ID (not username) of the reported user
- Idempotent

**Success criteria:**
- Both accept a valid Bearer token
- Both store the report persistently
- Neither throws 5xx when the same report is submitted twice
- Response is camelCase JSON

---

### 2. Implement user block / unblock endpoints ✅ RESOLVED 2026-07-07

**Why:** Apple Guideline 1.2 requires a mechanism to block abusive users.
Hard gate on App Store submission.

**Build:**

`POST /api/users/{id}/block`
```
Request: empty body or {}
Response 200: { "blocked": true }
```
- Idempotent (blocking an already-blocked user returns 200)
- Effect: blocked user's content is excluded from the caller's feed,
  replies, search results, and notifications — server-side enforcement
  is preferred; if not possible immediately, document a `blockedBy`
  flag on messages/users so the iOS client can filter locally

`DELETE /api/users/{id}/block`
```
Response 200: { "blocked": false }
```
- Idempotent (unblocking a non-blocked user returns 200)

`GET /api/user/blocks`
```
Response 200:
{
  "blockedUsers": [
    {
      "id": "string",
      "username": "string",
      "displayName": "string",
      "avatar": "url-string | null"
    }
  ],
  "pagination": { "total": int, "limit": int, "offset": int, "hasMore": bool }
}
```
- Accepts query params `?limit=` and `?offset=` for pagination
- All three endpoints require Bearer auth

---

### 3. Implement user mute endpoint (recommended, not strictly required) ✅ RESOLVED 2026-07-07

**Why:** A mute (softer than a block) is not strictly required by Apple 1.2,
but if a server-side mute exists it prevents re-surfacing muted content after
cache clears. If this doesn't exist server-side, iOS will implement local-only
muting — document that decision so the iOS client knows which path to take.

**Build (if implementing):**

`POST /api/users/{id}/mute` → `{ "muted": true }` (idempotent)
`DELETE /api/users/{id}/mute` → `{ "muted": false }` (idempotent)
`GET /api/user/mutes` → same pagination shape as `/api/user/blocks`

Semantics: muted users' content is hidden from the caller's feed and
notifications but the muted user is not told (unlike a block, which may
prevent them from interacting).

**If not implementing:** reply with `404` on `/api/users/{id}/mute` and the
iOS client will fall back to local-only muting.

---

### 4. Publish a Community Guidelines / EULA page ✅ RESOLVED 2026-07-07

**Why:** Apple 1.2 requires UGC apps to display a zero-tolerance community
agreement that users accept at registration. The iOS `RegisterView` needs a
live URL to link to. Without a live URL the terms-acceptance checkbox cannot
be wired up, and the app fails review.

**Build:** Create a publicly accessible page at one of:
- `https://interlinedlist.com/terms`
- `https://interlinedlist.com/guidelines`
- `https://interlinedlist.com/community`

Requirements:
- Returns HTTP 200 with no login required
- States a zero-tolerance policy for objectionable content and abusive behaviour
- Is linkable from the iOS registration screen (a webview link at sign-up) and
  from Settings → About

**Alternative:** the iOS app can present Apple's standard EULA instead of a
custom page. Decide which path to take and communicate the URL (or the Apple
EULA decision) to the iOS team so they can wire `RegisterView`.

---

## v1 TARGETS

### 5. Confirm and document push notification endpoint contracts ✅ RESOLVED 2026-07-07

**Why:** Phase 9 (APNs push notifications) ships in v1. The endpoints
reportedly exist (`POST /api/push/register`, `DELETE /api/push/unregister`)
but their contracts are unconfirmed. The iOS `PushService` needs the exact
request/response shapes before it can be built.

**Confirm:**

`POST /api/push/register`
```
Expected request (camelCase JSON, Bearer auth):
{ "token": "hex-device-token-string", "platform": "ios" }

Expected response:
{ "registered": true }
```

`DELETE /api/push/unregister`
```
Expected request: { "token": "hex-device-token-string" }
  — or — no body if the server unregisters the stored token for the
  authenticated user automatically
Expected response: { "unregistered": true }
```

**Also confirm:**
- Does the backend distinguish sandbox (TestFlight) vs production APNs
  environment? If so, how does it determine which to use — does the iOS
  client need to pass an `environment` field, or does the server infer it
  from the key type?
- What is the push payload shape the server sends? The iOS client needs
  the `actionUrl` field format to route tap events through the deep-link
  handler. Expected shape:
  ```json
  {
    "aps": { "alert": { "title": "…", "body": "…" }, "badge": 1, "sound": "default" },
    "actionUrl": "interlinedlist://…"
  }
  ```

---

### 6. Confirm or add org-author field to create-message endpoint ✅ CONFIRMED 2026-07-07

**Why:** Phase 15 (post on behalf of an organization) requires the
create-message endpoint to accept the posting organization as the author.
This field has not been confirmed to exist.

**Confirmed 2026-07-07:** `organizationId` is recognized — a probe with a non-member org
UUID returned `403 Forbidden: you must be an owner or admin of this organization`, confirming
the field is parsed and the auth check is enforced. No further backend work needed here.

**Confirm or add:**

`POST /api/messages` (camelCase body):
```json
{
  "content": "…",
  "organizationId": "org-uuid-here"
}
```
- `organizationId` is optional; omitting it means the authenticated user is
  the author (existing behaviour)
- The caller must be `owner` or `admin` of the specified org; return 403 otherwise
- The created message's author metadata should be the organization (name, avatar,
  slug) rather than the individual user
- The feed row and any reply context should show the org as author

**If the field doesn't exist:** add it and document the exact field name and
casing (camelCase expected). If the feature is not planned, reply so the iOS
team can formally defer Phase 15.

---

### 7. Make GET /api/user/identities accept Bearer tokens ✅ RESOLVED 2026-07-07

**Why:** This endpoint currently returns `401 Unauthorized` for a valid
Bearer token (confirmed 2026-07-02). It accepts session cookies only. Because
the iOS app is Bearer-only, the Mastodon/cross-post identity picker is
permanently empty — the app cannot discover which social accounts the user
has connected, so cross-posting is effectively blind.

**Fix (choose one):**

**Option A — Fix auth on the existing endpoint:**
Update `GET /api/user/identities` to accept a valid Bearer token the same
way `GET /api/user` does. No response shape change needed.

Expected response (confirm current shape):
```json
{
  "identities": [
    {
      "provider": "mastodon",
      "handle": "@user@techhub.social",
      "instanceUrl": "https://techhub.social",
      "connectedAt": "2026-01-01T00:00:00Z"
    },
    {
      "provider": "bluesky",
      "handle": "@user.bsky.social",
      "connectedAt": "2026-01-01T00:00:00Z"
    }
  ]
}
```

**Option B — Embed identities in GET /api/user:**
Add a `connectedIdentities` (or `identities`) array to the `GET /api/user`
response so a single authenticated call returns both user data and linked
providers. The iOS app already calls `/api/user` on login — bundling it
there eliminates the extra round-trip.

---

## QUALITY IMPROVEMENTS

These are not App Store blockers but they each require a server change and
are worth fixing before v1 if the effort is low.

### 8. Make GET /api/user/organizations accept Bearer tokens ⚠️ ACTIVE — found 2026-07-07

**Why:** `GET /api/user/organizations` returns `{"error":"Unauthorized"}` when called with a
valid Bearer token. Session-cookie auth works fine. Because the iOS app is Bearer-only, the
org list in the app is permanently empty — the same class of bug that was just fixed for
`GET /api/user/identities` (Prompt 7).

**Confirmed 2026-07-07:** When called with a session cookie the endpoint already returns
`userRole` and `memberCount` per org — so the response shape (the original ask) is already
correct; only the auth layer needs fixing.

**Fix:** Accept a valid Bearer token on `GET /api/user/organizations`, the same way
`GET /api/user` and (now) `GET /api/user/identities` do.

Confirmed response shape (no change needed):
```json
{
  "organizations": [
    {
      "id": "…",
      "name": "…",
      "slug": "…",
      "userRole": "owner" | "admin" | "member",
      "memberCount": 3,
      …
    }
  ]
}
```

---

### 9. Standardize pagination block on watcher list

**Why:** `GET /api/lists/{id}/watchers/users` returns `total` at the
top level instead of inside the `pagination` object. Every other endpoint
puts it inside `pagination`. This inconsistency broke the iOS decoder once.

**Fix:** Move `total` inside the `pagination` block:
```json
{
  "watchers": […],
  "pagination": { "total": 123, "limit": 20, "offset": 0, "hasMore": true }
}
```

---

### 10. Add role to GET /api/lists/{id}/watchers/me

**Why:** The endpoint returns only `{ "watching": bool }`. A non-owner
watcher can't learn their own role (watcher / collaborator / manager)
without fetching the full watcher list, which may be manager-gated. This
limits iOS's ability to show role-specific UI to list collaborators.

**Fix:**
```json
{ "watching": true, "role": "collaborator" }
```

---

### 11. Return the updated user from avatar endpoints

**Why:** `POST /api/user/avatar/upload` and `POST /api/user/avatar/from-url`
return only `{ "url": "…" }`. The iOS app must issue a follow-up `GET /api/user`
to refresh the avatar everywhere, adding a round-trip after every avatar change.

**Fix:** Return the full updated user object alongside the URL:
```json
{ "url": "https://…", "user": { …full user object… } }
```

---

### 12. Unify link metadata shape between feed and metadata endpoint

**Why:** Feed message objects expose link metadata as:
```json
linkMetadata.links[].metadata.thumbnail / .title / .description
```
But `POST /api/messages/{id}/metadata` returns:
```json
metadata.links[].image / .title / .description
```
Different wrapping, different key names (`thumbnail` vs `image`). iOS models
both shapes separately. One consistent schema would remove a whole decode path.

**Fix:** Standardize to the feed shape (nested `metadata` object with
`thumbnail`) since it is the primary read path. Update the `POST /{id}/metadata`
response to match.

---

### 13. Confirm POST /api/lists/{id}/watchers self-watch semantics

**Why:** The `POST /api/lists/{id}/watchers` body is `{ userId, role }` and
it's unclear whether `userId` is required for self-watch or whether omitting
it defaults to the authenticated user. The public "Watch this list" CTA in
iOS sends its own `userId` with `role: "watcher"` as a workaround.

**Clarify:** Is `userId` required for self-watch, or does the server default
to the authenticated caller? Document the self-watch path explicitly so the
iOS client doesn't need to send its own ID.

---

### 14. Confirm cross-post failure reporting shape

**Why:** Successful cross-posts return `crossPostUrls: [...]` on the created
message (confirmed). It's unconfirmed how the API signals a *failed*
cross-post. Does a failed platform appear in `crossPostUrls` with an error
field, get omitted entirely, or surface in a separate array?

**Clarify:** Document the failure path so the iOS toast can show ✓/✗
per platform rather than just listing successful destinations.

---

## DEFERRED — post-v1

Document these now so the contracts are on record; build after the first
App Store submission.

### 15. Bearer auth for GitHub integration (/api/github/*)

**Why:** `/api/github/*` requires session-cookie auth and rejects Bearer
tokens. iOS is Bearer-only. GitHub integration (Phase 11) is fully deferred
until this is resolved.

**Options:**
- Add Bearer token support to `/api/github/*` endpoints directly
- Implement `POST /api/auth/github/session` that exchanges a valid Bearer
  token for a short-lived session scoped only to GitHub endpoints

Do not add a cookie jar to the iOS client — it bypasses the Bearer security
model.

---

### 16. Tag discovery endpoints

**Why:** Tag filtering (`?tag=`) works but there's no discovery or autocomplete
path. Phase 13b (tag explorer + `#` autocomplete in Compose) is blocked on
these.

**Build:**

`GET /api/tags/trending`
```json
{ "tags": [ { "tag": "string", "count": int } ] }
```

`GET /api/tags/autocomplete?q=fo`
```json
{ "tags": ["foo", "football", "food"] }
```

---

### 17. Realtime feed / notification updates (WebSocket or SSE)

**Why:** Everything is pull-only today. APNs (Phase 9) covers the highest-value
push events. Realtime is a polish feature — new-post banners without a full
refresh, live notification badge updates.

**Build:** A WebSocket endpoint or SSE stream authenticated with Bearer token.
Events needed at minimum:
- `new_message` — a new feed item is available (client shows "New posts" banner)
- `notification` — a new notification arrived (client refreshes badge count)

Document the event envelope and auth handshake so Phase 17 can be scoped.

---

### 18. Document delta sync endpoint for offline documents

**Why:** Phase 16 (offline document sync) needs server support to
push/pull document changes efficiently.

**Build:**

`GET /api/documents/sync?lastSyncAt=ISO8601`
```json
{
  "documents": [ …documents changed or deleted since lastSyncAt… ],
  "deletedIds": ["id1", "id2"],
  "serverTime": "ISO8601"
}
```

`POST /api/documents/sync`
```
Request: { "edits": [ { "id": string, "content": string, "clientUpdatedAt": ISO8601 } ] }
Response: { "merged": [ …resolved docs… ], "conflicts": [ …docs where server won… ] }
```

Conflict resolution: last-write-wins per document (server clock wins on tie).
Conflicted docs should be returned so the iOS client can show a banner.

---

## Confirmed gaps for reference

Last audit: 2026-07-07.

| Ref | Gap | iOS workaround | Status |
|---|---|---|---|
| D0 | `GET /api/user/identities` returns 401 for Bearer tokens | Mastodon picker always empty | ✅ Resolved 2026-07-07 |
| D0b | `GET /api/user/organizations` returns 401 for Bearer tokens | Org list always empty | **Active — see Prompt 8** |
| B4 | `/api/github/*` requires session cookie, not Bearer | GitHub integration deferred | Deferred — Prompt 15 |
| B6 | No tag discovery endpoints | Tag explorer/autocomplete deferred | Deferred — Prompt 16 |
| B8 | No realtime (WebSocket/SSE) | Poll-only | Deferred — Prompt 17 |
| B10 | Moderation (report/block/mute) endpoints missing | Phase 14 blocked | ✅ Resolved 2026-07-07 |
| B10b | Community guidelines page missing | RegisterView terms link broken | ✅ Resolved 2026-07-07 |
| B11 | Push register/unregister contracts unconfirmed | PushService not built | ✅ Resolved 2026-07-07 |
| C2 | Watcher list pagination has `total` at top level, not in `pagination` | Special-cased decoder | Quality — Prompt 9 (unverified) |
| C3 | Self-watch `userId` requirement unclear | iOS sends own userId | Quality — Prompt 13 (unverified) |
| D1 | Cross-post failure shape unconfirmed | Toast shows only successes | Quality — Prompt 14 (unverified) |
| D2 | `linkedInTargets[].kind` vocabulary undocumented | Boolean-only cross-post | Deferred with Phase 18 |
| E | Avatar endpoints don't return updated user | Extra `GET /api/user` after upload | Quality — Prompt 11 (unverified) |
