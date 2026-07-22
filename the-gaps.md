# The Gaps — InterlinedList iOS ↔ interlinedlist.com

Single source of truth for **(a)** the iOS↔web feature/parity gaps the iOS team
owns, and **(b)** the backend/API work the `interlinedlist.com` team owns to
unblock mobile. Merged from the two former gap docs — the backend-asks audit and
the iOS work list — now consolidated here.

**Prepared:** 2026-07-18 (live read-only API probes)
**Merged & updated:** 2026-07-22

**Sources:**
1. The shipped iOS client's `APIClient.swift` — a production HTTP client that
   actually calls these endpoints.
2. The public docs at `https://interlinedlist.com/help/api/*` (all detail pages
   read verbatim 2026-07-18; targeted re-read 2026-07-22 for lists).
3. **Live read-only probes** against production (2026-07-18) using the
   `messenger@interlinedlist.com` test account (a **subscriber**). Probes were
   GETs, `OPTIONS` (for `Allow`-header verb detection), and the login POST only —
   **no data was mutated.**

**Owner/status legend:**
**[BACKEND]** the API blocks the mobile client (Bearer rejected) ·
**[DOC]** docs are wrong/incomplete · **[iOS]** the client is wrong (we fix it) ·
**[VERIFY]** still needs a write-test or a non-subscriber account.
Status: **OPEN** · **RESOLVED** · **BLOCKED** (needs a backend change first).

> Scope note: this is the **iOS** app. The web site lists an "iOS App (Coming
> Soon)" and a separate "macOS App (Coming Soon)"; no native macOS target exists
> in this repo.

---

## Part I — The one systemic finding

**Several whole feature areas reject Bearer tokens and only accept a session
cookie.** The iOS app is **Bearer-only** (it has no cookie jar), so these
features are simply unreachable from mobile. Confirmed live (401 with a valid
Bearer) and/or stated in the API's own docs:

| Area | Endpoint(s) | Bearer? | Consequence for iOS |
|---|---|---|---|
| CSV Exports | `GET /api/exports/*` | ❌ 401 (confirmed live) | Export feature is **dead** in the shipped app (D4/F1) |
| GitHub | `GET/POST/PATCH /api/github/*` | ❌ (docs: "not accepted") | GitHub-backed lists & issues **cannot be built** for iOS (§2.1/F3) |
| LinkedIn targets | `GET/PUT /api/linkedin/posting-targets` | ❌ 401 (confirmed live) | LinkedIn org/target picker **cannot be built** for iOS (§2.3/F2) |

**The single highest-value thing the backend can do for mobile parity is add
Bearer-token support to these endpoints** (see Prompt A). Everything else is
smaller.

---

## Part II — iOS work (what we build / fix)

### II.0 — Confirmed defects to fix first (found via live probe)

Each is a **client bug** (or a backend-auth blocker) in already-shipped
functionality. Backend-side detail is in Part III (F-items). **Status column
re-verified against `APIClient.swift` on 2026-07-22 — all still OPEN.**

| # | Symptom | Root cause | Fix | Status |
|---|---|---|---|---|
| D1 (↔F8) | Editing profile / theme / default-visibility / avatar-from-URL silently fails | `POST /api/user/update`; server allows **only `PATCH`** (405), and expects camelCase | Switch the three `/api/user/update` calls to `patchCamel` | **OPEN** — still `post` (`APIClient.swift:229,789,804`) |
| D2 (↔F9) | Editing a posted message fails | `editMessage` uses `PUT /api/messages/:id`; server allows **`PATCH`, not `PUT`** (405) | Switch `editMessage` to `patchCamel` (`{content, publiclyVisible}`) | **OPEN** — still `put` (`APIClient.swift:358`) |
| D3 (↔F10) | Marking a notification read fails | `markNotificationRead` uses `PUT /api/notifications/:id/read`; server allows **only `PATCH`** (405) | Switch to a `PATCH` request (empty body) | **OPEN** — still `put` (`APIClient.swift:726`) |
| D4 (↔F1/F11) | CSV export always fails | `exportCSV` sends Bearer; `/api/exports/*` is **session-cookie-only** (401) | Backend-blocked (Prompt A). Until then, hide the Export UI | **OPEN/BLOCKED** — still Bearer (`APIClient.swift:831`) |
| D5 (↔F12) | Push may never arrive | `registerPushDevice` sends body `{token}`; docs specify `{deviceToken}` | Confirm handler field; likely rename `token` → `deviceToken` | **OPEN/VERIFY** — sends `token` (`APIClient.swift:1167–1170`) |

**Prompt for Claude — fix D1/D2/D3 (verb + casing):**
> In `InterlinedList/Services/APIClient.swift`, three writes use the wrong HTTP
> method (confirmed against production via `OPTIONS` Allow headers):
> 1. `updateProfile`, `updateUserSettings`, and `applyAvatarUrl` all call
>    `post("/api/user/update", …)`. The server allows **only `PATCH`** and expects
>    a **camelCase** body. Change them to `patchCamel`. Keep the `{user?}`-unwrap.
> 2. `editMessage` calls `put("/api/messages/:id", …)`; the server allows `PATCH`
>    not `PUT`. Change it to `patchCamel` with `{ content, publiclyVisible }`.
> 3. `markNotificationRead` calls `put("/api/notifications/:id/read", …)`; the
>    server allows only `PATCH`. Change it to a `PATCH` request (empty body).
> Update the `MockURLSession` unit tests to assert `PATCH` and the camelCase body
> keys. Do NOT change `patchScheduledMessage` (already correct). Then smoke-test
> in the simulator: edit profile, edit a message, mark a notification read.

**Prompt for Claude — D4 (exports) + D5 (push):**
> 1. Exports: `exportCSV` sends a Bearer token, but `/api/exports/*` rejects Bearer
>    (401, confirmed live) — session-cookie-only. Until the backend adds Bearer
>    support (Prompt A / F1), **hide the Export entry point** and leave a
>    `// TODO: re-enable when /api/exports accepts Bearer` note.
> 2. Push: `registerPushDevice`/`unregisterPushDevice` send `{ token }`; the docs
>    specify `{ deviceToken }`. Confirm the handler field (ask backend or
>    write-test), rename the client field to `deviceToken` if needed, and add a
>    unit test asserting the body key. This is a silent-failure path — prioritize.

### II.1 — Conventions every iOS prompt assumes (from `CLAUDE.md`)

- **Encoders:** `get` / `postCamel` / `putCamel` / `patchCamel` for camelCase
  bodies (most endpoints); `post`/`put`/`patch` for snake_case. Check the existing
  method before adding one — mismatches fail **silently** server-side.
- **401 contract:** never log out on a feature-endpoint 401; route through
  `authState.handleUnauthorized()` (re-validates against `GET /api/user`).
- **Subscriber gating = hide, never disable/paywall.** Gate on
  `authState.user?.isSubscriber == true`. **No** billing/upgrade/price copy and
  **no** link to interlinedlist.com to pay (App Store Guideline 3.1.1).
- **Standards:** no comments unless the "why" is non-obvious; no force-unwrap;
  `@MainActor` over `DispatchQueue.main.async`; `.accessibilityLabel` on every
  control; a `#Preview` in every View file.
- **New files must be registered** in `project.pbxproj` (no synced groups) — use
  the `xcodeproj` Ruby gem.
- **Tests:** add `MockURLSession` unit tests for every new/changed `APIClient`
  method (assert method, path, encoder casing, decode of happy + error paths).

### II.2 — Parity matrix

Legend: ✅ at parity · ◑ partial · ❌ missing · 🔴 broken · — n/a

| Web capability | iOS | Notes |
|---|---|---|
| Email/password + OAuth (Mastodon, Bluesky, LinkedIn, Twitter) | ✅ | GitHub sign-in intentionally hidden |
| Feed, link previews, dig, reply, delete, search | ✅ | |
| **Edit a posted message** | 🔴 | D2 — uses unsupported `PUT` (405) |
| Compose: image/video, scheduled, cross-post, repost, post-as-org | ✅ | multi-image (≤8) + drag-reorder + normalization shipped; post-as-org = Phase 15 |
| **Edit profile / settings / avatar-from-URL** | 🔴 | D1 — uses unsupported `POST` (405) |
| **Mark notification read** | 🔴 | D3 — uses unsupported `PUT` (405) |
| Lists: CRUD, folders, schema editor, rows, connections, watchers | ✅ | create-list schema contract fixed 2026-07-22 (F15) |
| Documents: CRUD, folders, search, inline images, public reader | ✅ | inline images = Phase 10; free-user create gate unverified (§2.9/F13) |
| Follow graph, organizations, notifications (tray/prefs), moderation, push | ✅ | push field name unverified (D5) |
| **CSV exports** | 🔴 | D4 — `/api/exports/*` rejects Bearer (session-only) |
| **GitHub-backed lists / GitHub issues** | ❌ | §2.1 — backend-blocked (Bearer rejected, confirmed) |
| **Tag discovery / trending** | ◑ | §2.2 — can filter by tag; no discovery UI; endpoint unconfirmed |
| **LinkedIn org/target picker** | ◑ | §2.3 — backend-blocked (targets are session-only, confirmed) |
| **Document templates** | ❌ | §2.4 — endpoint confirmed live over Bearer; ready to build |
| **Content deep links / universal links** | ❌ | §2.5 — only auth callbacks routed |
| **Multi-account switching** | ❌ | §2.6 — web has `/api/auth/accounts`,`/switch`,`/remove-account`; iOS single-account |
| **Realtime updates** | ❌ | §2.7 — no realtime endpoint found; poll/refresh only |
| **Offline document sync** | ❌ | §2.8 — `/api/documents/sync` exists & is Bearer-accessible (confirmed); buildable |
| Utility widgets (weather/geolocation) | ❓ | §2.9 — confirm if user-facing list column types |
| Admin console | — | not an app feature |
| Subscription/billing UI | — | web-only by design; must never appear on iOS |

### II.3 — The gaps, prioritized

#### Tier A — Ready to build now (backend confirmed working over Bearer)

**§2.4 Document templates** `Small` ✅ backend-ready.
Confirmed live: `GET /api/documents/templates` → `{ folderCreated,
templatesFolderId, templates:[{id,title,…}] }` over Bearer (200). Web also has
`POST /api/documents/from-template` (subscriber-only) and
`POST /api/documents/templates/seed-defaults`. iOS status: ❌ new docs start blank.
> Add `APIClient.documentTemplates()` returning `[DocumentTemplate]` (inspect the
> live response for exact keys). In the create-document flow in `DocumentsView`,
> add an optional "Start from template" picker that prefills title/content. If you
> wire `POST /api/documents/from-template`, gate on `isSubscriber` and hide
> otherwise. Add `MockURLSession` tests and a `#Preview`.

**§2.5 Content deep links / universal links** `Small–Medium`.
`InterlinedListApp.handleDeepLink` only routes `reset-password`, `verify-email`,
`verify-email-change`, `oauth`. No content permalinks, no Universal Links.
> Extend `AppRouter` + `InterlinedListApp.handleDeepLink` to route content
> permalinks: user profiles, public lists
> (`/api/users/:username/lists/:id` → `PublicListDetailView`), public documents,
> single message threads. Support both `interlinedlist://…` and
> `https://interlinedlist.com/…` via `.onOpenURL`. Mind the confirmed
> public-browse namespace split: messages are `/api/user/:username/messages`
> (singular) while lists/documents are `/api/users/:username/…` (plural) — the
> wrong one 404s. Universal Links also need the backend to publish
> `apple-app-site-association` + the Associated Domains entitlement (**record that
> dependency in this doc, Part III**); the custom-scheme path works without it.
> Add a share action (web permalink) on message/list/profile.

**§2.8 Offline document sync** `Large` ✅ backend-ready (contract exists).
Confirmed live: `GET /api/documents/sync` → `{ folders:[…], … }` over Bearer
(200) — the same delta-sync contract the web's `il-sync` CLI uses.
> Inspect the full `GET`/`POST /api/documents/sync` contracts against production
> (revision/`updatedAt` fields, delta vs full-body, conflict signals) and record
> in this doc (Part III). Then design (and land a minimal slice of) offline doc
> editing: cache edits in `DataCache`, replay via the sync endpoint on reconnect,
> resolve conflicts last-writer-wins or with a simple prompt. Feature-flag it.
> Ship the read-then-queue slice first, then two-way sync.

#### Tier B — Backend-blocked (endpoints reject Bearer; need a backend change first)

**§2.1 GitHub-backed lists & GitHub integration** `Large` ⛔ BACKEND (confirmed).
Web lists are "local or **GitHub-backed**"; `/api/github/*` covers repos, issues,
labels, assignees. Confirmed blocker: every `/api/github/*` endpoint requires a
session cookie — "Bearer tokens are not accepted" (F3). Biggest single parity gap.
> Do NOT build UI yet — backend-blocked. Confirm with the backend owner when
> `/api/github/*` will accept Bearer (Prompt A / F3). Meanwhile produce an
> implementation plan only: models + `APIClient` methods for `GET /api/github/repos`
> and `GET /api/github/issues?repo=owner/repo`, a repo picker in `CreateListView`
> for GitHub-backed lists, and a read-only issues view. Escalate the Bearer-auth
> requirement as the gating dependency.

**§2.3 LinkedIn org/target picker** `Small` ⛔ BACKEND (confirmed).
`GET /api/linkedin/posting-targets` → **401 to Bearer** (session-only, per docs +
live probe). The `linkedInTargets` field on `POST /api/messages` already works; we
just can't fetch the target list on mobile. Response shape is known:
`{ targets:[{ kind: personal|orgPage|personalPage, label, pageId|personalPageId,
linkedInPageId, enabled }], orgScopeMissing }`; posting uses `pageId`/
`personalPageId` in `linkedInTargets`.
> Backend-blocked: `/api/linkedin/posting-targets` rejects Bearer. Once the backend
> adds Bearer support (Prompt A / F2), add `APIClient.linkedInPostingTargets()`
> returning `[LinkedInTarget]` (map `pageId`/`personalPageId` into the existing
> `linkedInTargets` field). In `ComposeView`, when the LinkedIn toggle is on and
> the user is a subscriber, show a target picker + the existing "link as first
> comment" toggle. Hide for non-subscribers / no LinkedIn identity.

**§2.2 Tag discovery / trending** `Small` ❓ needs discovery.
"Hashtag organization and discovery" is marketed, but the client only supports a
`tag` filter (`messages(tag:)`). No trending-tags endpoint is confirmed.
> Probe for a trending/known-tags endpoint against production with the E2E `.env`
> token (`GET /api/tags/trending`, `/api/tags`, `/api/messages/tags`). Record the
> real path/shape in this doc (Part III). If one exists, add
> `APIClient.trendingTags()`, a model, a "Discover" surface in `FeedView`, and make
> in-body `#hashtags` tap through to the existing `tag:` feed. If none exists,
> document as backend-blocked and stop. Tests + `#Preview`.

**§2.7 Realtime updates** `Large` ⛔ likely BACKEND.
No realtime endpoint appears in the docs and none was probed. Poll/refresh only.
> Discovery only: determine whether production exposes a realtime channel
> (`/api/stream`, `/api/events`, `/ws`, SSE `text/event-stream`). Record in this
> doc (Part III). If present, propose a `RealtimeService` (`@MainActor`,
> reconnect/backoff) layered on the existing cache-then-refresh model. Build
> nothing until confirmed; feature-flag when built.

#### Tier C — Smaller / investigate

**§2.6 Multi-account switching** `Small`.
Web auth docs list `GET /api/auth/accounts`, `POST /api/auth/switch`,
`POST /api/auth/remove-account` (and `?all=true` logout) — a cached multi-account
switcher. iOS is single-account.
> Confirm those three accept Bearer (probe with the E2E token). If so, add an
> account switcher to `SettingsView`/profile: list cached accounts, switch active
> account (swap the Keychain token + `AuthState`), remove an account. Gate behind
> having >1 account. Tests + `#Preview`.

**§2.9 Document creation gate + utility widgets** `Investigate`.
- **Documents gate:** docs mark `POST /api/documents` **subscriber-only**, but the
  iOS product direction assumes documents are free. Our probe account is a
  subscriber, so unverified. Test with a **non-subscriber** account: if creation
  403s for free users, hide the create-document UI for them; if it succeeds, the
  docs are wrong (F13).
- **Utility widgets:** `/help/api/utility-endpoints` exists (weather, geolocation,
  image-proxy, oauth-metadata). Investigate whether weather/geolocation are
  user-facing **list column types** on the web; if so, `ListSchemaEditorView` is
  missing those column types (a real lists-parity gap). Findings only this pass.

### II.4 — Suggested execution order

1. **Defects D1–D5** — broken shipped features. Fix D1/D2/D3 immediately (one
   `APIClient` PR), confirm D5 (push field), hide the export UI (D4) until the
   backend unblocks it. Highest priority.
2. **Backend asks** — file Prompt A with the backend team: Bearer support on
   `/api/exports/*`, `/api/linkedin/*`, `/api/github/*`. Unblocks D4 + §2.1 + §2.3
   in one move.
3. **Ready-now features** — §2.4 (templates), §2.5 (deep links); then §2.8
   (offline doc sync — contract confirmed Bearer-accessible).
4. **After Bearer unblock** — §2.1 (GitHub-backed lists, biggest win) and §2.3
   (LinkedIn target picker).
5. **Discovery-dependent** — §2.2 (tags), §2.6 (multi-account), §2.7 (realtime),
   §2.9 (doc gate + utility widgets).

### II.5 — Housekeeping (doc drift, from prior assessment)

Two "deferred" phases actually shipped and should read as done in the tracking
docs (already reflected in the parity matrix above):

| Phase | Old status | Reality |
|---|---|---|
| **10 — Inline document image upload** | Tier 1, unchecked | ✅ Done (`uploadDocumentImage`; `DocumentsView.swift`) |
| **15 — Post as organization** | Tier 1, unchecked | ✅ Done (`postMessage(organizationId:)`; `ComposeView.swift`) |

> Docs-only follow-up: in `App-Store-Deployment.md`, move Phase 10 and Phase 15
> into "What's Already Shipped" and add defects D1–D5 to the tracking docs as bugs
> (they affect already-shipped functionality).

---

## Part III — Backend / API team asks

### III.0 — Findings at a glance (all CONFIRMED unless noted)

| # | Owner | Finding | Status | Evidence |
|---|---|---|---|---|
| F1 | **BACKEND** | `GET /api/exports/*` rejects Bearer (session-only) | OPEN | Live: 401 w/ valid Bearer + no-auth |
| F2 | **BACKEND** | `GET/PUT /api/linkedin/posting-targets` rejects Bearer | OPEN | Live: 401; docs say "Auth: Session" |
| F3 | **BACKEND** | All `/api/github/*` reject Bearer | OPEN | Docs: "Bearer tokens are not accepted" |
| F4 | **DOC** | Messages page **auth column is unreliable** — `/api/messages/:id/replies` marked "Session" but returns **200 with no auth** | OPEN | Live: 200 Bearer + 200 no-auth |
| F5 | **DOC** | **No Moderation docs section exists**, but report/block/mute are live | OPEN | Live: `GET /api/user/blocks` & `/mutes` → 200 (Bearer) |
| F6 | **DOC** | `POST /api/user/organizations` documented as "Create" but client uses it to **join** | OPEN | Client sends `{organizationId}`; docs say "create" |
| F7 | **DOC** | Document **folder path-scoping** has no warning — root routes silently ignore folders | OPEN | Docs omit the caveat; causes silent data-loss |
| F8 (↔D1) | **iOS** | Client uses `POST /api/user/update`; server allows **only `PATCH`** → 405 | iOS OPEN | Live OPTIONS `Allow: OPTIONS, PATCH` |
| F9 (↔D2) | **iOS** | Client uses `PUT /api/messages/:id`; server allows **`PATCH`, not `PUT`** → 405 | iOS OPEN | Live OPTIONS `Allow: …, PATCH` |
| F10 (↔D3) | **iOS** | Client uses `PUT /api/notifications/:id/read`; server allows **only `PATCH`** → 405 | iOS OPEN | Live OPTIONS `Allow: OPTIONS, PATCH` |
| F11 (↔D4) | **iOS** | Client sends Bearer to exports (see F1) → export dead | iOS OPEN/BLOCKED | Live 401 |
| F12 (↔D5) | **VERIFY** | Push body field: docs say **`deviceToken`**, client sends **`token`** → likely silent push failure | OPEN | Not write-tested; verb/path confirmed |
| F13 | **VERIFY** | `POST /api/documents` documented **Subscriber-only**; iOS assumes documents **free** | OPEN | Subscriber account couldn't observe free path |
| F14 | **DOC** | `crossPostResults[].platform` can be omitted (crashed a strict decoder) | iOS-patched; doc OPEN | Client made it optional |
| F15 | **iOS** | `POST /api/lists` sent DSL **string** + read `list` key; server wants a DSL **object** + returns `data` | **RESOLVED 2026-07-22** | `createList` now sends object, decodes `data` (`APIClient.swift:422–427`) |
| F16 | **DOC** | Docs previously showed `POST /api/lists` `"schema":"string"`; now corrected to object form | **RESOLVED 2026-07-22** | `/help/api/lists`, `/help/api/lists-dsl` now object; response envelope still undocumented (residual) |

### III.1 — [BACKEND] Endpoints that reject Bearer and block the mobile client

**F1 — CSV Exports are session-only (confirmed).**
```
GET /api/exports/messages       [Bearer]  -> 401 {"error":"Unauthorized"}
GET /api/exports/lists          [Bearer]  -> 401
GET /api/exports/follows        [Bearer]  -> 401
GET /api/exports/list-data-rows [Bearer]  -> 401
GET /api/exports/messages       [no auth] -> 401
```
Docs correctly state exports don't accept Bearer — so the docs are right and the
iOS export feature is broken (it sends Bearer and always 401s). To make export
work on mobile, **add Bearer support to `/api/exports/*`**. (Your docs also list a
`list-data-rows` export the client doesn't know about — we may add it once auth
works.)

**F2 — LinkedIn posting-targets are session-only (confirmed).**
```
GET /api/linkedin/posting-targets [Bearer] -> 401
```
Docs (`/help/api/linkedin-integration`) confirm "Auth: Session" for
`/api/linkedin/targets`, `/api/linkedin/posting-targets` (GET+PUT), and
`/api/linkedin/sync-pages`. The composer's `linkedInTargets` field on
`POST /api/messages` already works, but iOS **can't fetch the target list**.
**Add Bearer support to the LinkedIn targets endpoints** and the picker becomes
buildable. (Response shape `{targets:[{kind, label, pageId|personalPageId,
linkedInPageId, enabled}], orgScopeMissing}` is documented — exactly what we need.)

**F3 — GitHub integration is session-only.**
Docs (`/help/api/github-integration`): every `/api/github/*` endpoint requires a
session cookie ("Bearer tokens are not accepted") plus a linked GitHub identity,
and these "power features like GitHub-backed lists" — a headline web feature iOS
can't reach. **Add Bearer support to `/api/github/*`** to unblock native
GitHub-backed lists.

### III.2 — [DOC] Documentation fixes

**F4 — Audit the Messages page auth column (it's demonstrably wrong).**
`/help/api/messages` marks `GET /api/messages/:id/replies`, `POST /:id/dig`,
`DELETE /:id/dig`, and `PATCH /:id` as **Session**. But live:
```
GET /api/messages/:id/replies [Bearer]  -> 200
GET /api/messages/:id/replies [no auth] -> 200   (effectively public for public messages)
```
Re-audit the whole column against the actual middleware — where Bearer works, say
"Session or Bearer"; where public, say "Public." Treat the whole column as suspect
given `replies` was mislabeled.

**F5 — Add a Moderation section (endpoints exist and are live).**
No `/help/api/moderation` page exists. These are live and Bearer-accepted (Apple
requires them for our app):
```
GET /api/user/blocks?limit=1 [Bearer] -> 200 {"blockedUsers":[],"pagination":{...}}
GET /api/user/mutes?limit=1  [Bearer] -> 200 {"mutedUsers":[],"pagination":{...}}
```
The client also uses (writes, not probed): `POST /api/messages/:id/report`,
`POST /api/users/:id/report`, `POST|DELETE /api/users/:id/block`,
`POST|DELETE /api/users/:id/mute`. Document all of them (paths, bodies — reports
take `{reason, detail?}` — auth, response shapes) and link from the index.

**F6 — Clarify `POST /api/user/organizations`: create vs. join.**
`/help/api/users-and-profile` documents it as "Create new organization." The iOS
client calls it with `{ organizationId }` to **join** an existing org (it creates
orgs via `POST /api/organizations`). Clarify the real semantics (create/join/
body-dependent) and the canonical join route. `GET /api/user/organizations` (list
my orgs) — confirmed live 200 — is documented now; good.

**F7 — Add a folder path-scoping warning to Documents / Document Folders.**
Neither page warns that:
- `GET /api/documents` returns **only root docs** and **ignores `?folderId`**.
- `POST /api/documents` **always creates at root** (no `folderId` field).
- Only `PATCH /api/documents/:id` accepts `folderId` (to move).

Using the root routes for folder content **silently drops docs to root**. A
prominent callout on both pages would save every future integrator this bug.

**F14 — Document the `crossPostResults` shape (mark `platform` optional).**
On `POST /api/messages` with cross-posting, response `crossPostResults[]` entries
sometimes **omit `platform`** (observed with Bluesky), which crashed a strict
decoder. Document the shape and which fields are optional, or always emit
`platform`.

### III.3 — [iOS] Verb/auth mismatches we will fix (your docs are right)

Client bugs confirmed via live `OPTIONS` `Allow` headers — fixed on our side (see
D1–D4). Listed so you know (a) your docs are correct and (b) if you'd rather accept
the client's verb too, that's an option.

| Endpoint | Server allows | Client sends | Result | Our fix |
|---|---|---|---|---|
| `/api/user/update` | `OPTIONS, PATCH` | `POST` | 405 → profile/settings/avatar writes fail | switch to `patchCamel` |
| `/api/messages/:id` (edit) | `…, PATCH` (no `PUT`) | `PUT` | 405 → message edit fails | switch to `patchCamel` |
| `/api/notifications/:id/read` | `OPTIONS, PATCH` | `PUT` | 405 → mark-read fails | switch to `PATCH` |
| `/api/exports/*` | session cookie only | Bearer | 401 → export dead | needs your F1 fix |

> Accepting **both** `POST` and `PATCH` on `/api/user/update`, and **both** `PUT`
> and `PATCH` on the edit routes, would make the API more forgiving — not required;
> we'll align the client regardless.

### III.4 — [VERIFY] Two items we couldn't confirm read-only

**F12 — Push registration body field (`token` vs `deviceToken`).**
Path and verb are correct (`POST /api/push/register`, `DELETE /api/push/unregister`
— confirmed via `Allow`). But docs show the body field as **`deviceToken`** while
the client sends **`token`** (`APIClient.swift:1167–1170`). If the handler reads
`deviceToken`, iOS device tokens are **silently dropped** (no error, no push).
Confirm the handler field name (we'll rename) or accept `token` as an alias.
Highest-impact silent-failure candidate remaining.

**F13 — Is document creation subscriber-only or free?**
`/help/api/documents` marks `POST /api/documents` (and image upload, template
creation) **Subscriber only**. The iOS product direction assumes documents are
**free**. Our test account is a subscriber, so we couldn't observe the free path.
Confirm the real gate. If subscriber-only, free iOS users silently can't create
docs and we must hide that UI; if free, drop the "Subscriber only" label.

### III.5 — Confirmed-CORRECT (please do NOT "fix" these)

Live-verified that docs and client already agree:
- `POST /api/user/delete` — `Allow: OPTIONS, POST` ✓
- `POST /api/user/avatar/from-url`, `POST /api/user/avatar/upload` ✓
- `POST /api/notifications/mark-all-read` ✓; `GET /api/notifications` requires
  `scope=tray` (400 without) ✓
- `GET /api/user/notification-preferences` + `PATCH` ✓
- `GET /api/user/identities`, provider `status` for LinkedIn/Twitter only ✓
- Public-browse namespace split is **real and load-bearing** (do not "normalize"):
  - `GET /api/user/:username/messages` (singular `user`) → 200; plural form → **404**
  - `GET /api/users/:username/lists` / `/lists/:id/data` / `/documents` (plural
    `users`) → 200; singular form → **404**
  - Recommend documenting the split explicitly — it's a footgun even though intentional.
- `GET /api/documents/templates`, `GET /api/documents/sync` — live 200 over Bearer ✓

### III.6 — Ready-to-paste prompts for the site/API team

**Prompt A — Add Bearer support to the session-only feature areas (highest value).**
> Our iOS app authenticates with Bearer tokens only (no session cookie). Live
> probing on 2026-07-18 confirmed these return 401 to a valid Bearer:
> `GET /api/exports/{messages,lists,follows,list-data-rows}` and
> `GET /api/linkedin/posting-targets`; and the docs state `/api/github/*` also
> reject Bearer. In the API, extend the auth middleware for `/api/exports/*`,
> `/api/linkedin/*`, and `/api/github/*` to accept `Authorization: Bearer <token>`
> the same way `/api/messages` and `/api/user` already do. If any must stay
> session-only for a security reason, document that explicitly and tell us so we
> can drop those features from mobile. Then update each page's Auth column.

**Prompt B — Fix the Messages auth column and add a Moderation section.**
> 1. On `/help/api/messages`, the Auth column is wrong: `GET /api/messages/:id/replies`
>    is marked "Session" but returns 200 with a Bearer token AND with no auth at
>    all. Re-audit every row against the actual middleware and correct the column
>    ("Session or Bearer" / "Public"), especially `replies`, `dig`, `undig`,
>    `PATCH /:id`.
> 2. Add a **Moderation** docs page. These are live: `GET /api/user/blocks`,
>    `GET /api/user/mutes`, `POST /api/messages/:id/report`,
>    `POST /api/users/:id/report`, `POST|DELETE /api/users/:id/block`,
>    `POST|DELETE /api/users/:id/mute`. Document paths, bodies (reports take
>    `{reason, detail?}`), auth, and response shapes; link it from the index.

**Prompt C — Clarify org-join and add the doc-folder warning.**
> 1. `/help/api/users-and-profile` documents `POST /api/user/organizations` as
>    "Create new organization," but our client posts `{ organizationId }` to it to
>    JOIN an existing org (it creates via `POST /api/organizations`). Clarify the
>    real behavior and document the canonical join route.
> 2. On `/help/api/documents` and `/help/api/document-folders`, add a prominent
>    warning: `GET /api/documents` ignores `?folderId` and `POST /api/documents`
>    always writes to root; to create/list inside a folder you MUST use
>    `/api/documents/folders/:id/documents`. The root routes silently drop docs to
>    root.

**Prompt D — Confirm two ambiguous contracts.**
> 1. Push: does the `POST /api/push/register` / `DELETE /api/push/unregister`
>    handler read `deviceToken` or `token`? Our client sends `token`; your docs
>    show `deviceToken`. If it reads `deviceToken`, our tokens are silently dropped
>    — accept `token` as an alias or tell us to rename.
> 2. Documents: is `POST /api/documents` truly subscriber-only (as documented) or
>    free? It changes whether our iOS app must hide document creation from free
>    users. Confirm against the handler.

**Prompt E — Document the crossPostResults response shape.**
> On `POST /api/messages` with cross-posting, document the exact shape of
> `crossPostResults[]` and mark optional fields — in particular `platform` is
> sometimes omitted (observed for Bluesky), which crashed a strict client decoder.
> Either always include `platform` or document it as optional.

### III.7 — Addendum: the `POST /api/lists` schema contract (2026-07-22)

A real user hit **`400 "Invalid Schema: DSL must be an object"`** creating a list.
Root-causing surfaced one client bug (F15, fixed) and one doc problem the backend
had already largely fixed (F16).

**F15 — [iOS, RESOLVED] client sent a DSL *string* and read the wrong response key.**
The shipped client built `schema` as the legacy comma-separated DSL **string**
(`"Title:text, Author:text"`) and decoded the created list from a **`list`** key.
The server (`validateDSLSchema` in `lib/lists/dsl-parser.ts`) requires `schema` to
be a DSL **object** and returns the created list under **`data`**. Fixed
2026-07-22 — `createList` now sends the object and decodes `data`
(`APIClient.swift:422–427`):
```jsonc
// POST /api/lists — request body the client now sends
{
  "title": "Books to Read",
  "isPublic": true,
  "schema": {                      // object, NOT "Title:text, Author:text"
    "name": "Books to Read",
    "fields": [
      { "key": "title", "type": "text", "label": "Title", "displayOrder": 0,
        "required": false, "visible": true }
    ]
  }
}
// 201 response — list is under `data`
{ "message": "List created successfully", "data": { "id": "lst_…", "properties": [ … ] } }
```

**F16 — [DOC, RESOLVED] the docs used to show the string form; residual response gap.**
As of 2026-07-18 both `/help/api/lists` and canonical `docs/api-reference.md`
documented `POST /api/lists` with **`"schema": "string"`** — exactly the request
the server rejects. Re-checked 2026-07-22: fixed. `/help/api/lists`, the new
dedicated **`/help/api/lists-dsl`** reference, and `docs/api-reference.md:2709` all
now show the DSL **object**. Two small residuals:
1. **Response body isn't documented.** The `POST /api/lists` section still lists
   only status codes (201/400/401/403), so the `{ message, data: { … } }` envelope
   is undocumented. A one-line example would prevent the next client from decoding
   the wrong key.
2. **Subscriber gate.** The route is `[Subscriber]`-only and returns
   `403 "Subscribe to create lists."` for non-subscribers (same family as F13).
   Flagged as **[VERIFY, iOS]** to confirm our app surfaces that 403 gracefully.

---

## Part IV — Coverage & method notes

**Docs pages read verbatim (2026-07-18):** `/help/api` and all detail pages —
`authentication`, `users-and-profile`, `public-profiles`, `messages`, `following`,
`lists`, `list-folders`, `documents`, `document-folders`, `notifications`,
`push-notifications`, `exports`, `organizations`, `github-integration`,
`linkedin-integration`, `utility-endpoints`, `administration`. (No `moderation`
page — that's F5.)

**Re-review 2026-07-22 (targeted):** `/help/api`, `/help/api/lists`, the new
`/help/api/lists-dsl` page, and `docs/api-reference.md` §`POST /api/lists`,
prompted by a live `400 "Invalid Schema: DSL must be an object"` (Part III.7).

**Live probe (read-only) on 2026-07-18, account `messenger` (subscriber):** login
(POST sync-token), ~30 GETs, and `OPTIONS` verb-detection on 15 routes. No writes.

**Not tested (would require writes or a different account):** push body-field
behavior (F12/D5), create-vs-join semantics of `POST /api/user/organizations`
(F6), free-user document-creation gate (F13/§2.9), `dig`/`undig` auth (F4). We're
happy to run authorized write-tests for any of these.

**Recommendation:** diff Part III against the OpenAPI/route table. The
client-contract items (III.3) and the Bearer-rejection items (III.1) are where a
real, shipped consumer already diverges from the platform today.

## Bottom line

Core product is at parity **except for the shipped features that regressed to
broken** (Part II.0, D1–D5) — fixing those is the immediate priority and mostly a
one-file `APIClient` change. Beyond that, full web parity needs the backend to
**accept Bearer tokens on exports/GitHub/LinkedIn** (one systemic fix unblocking
three features), then a handful of self-contained additions (templates, deep
links, multi-account, tag discovery) and two larger systems (offline doc sync —
now confirmed buildable; realtime — still needs a backend endpoint).
