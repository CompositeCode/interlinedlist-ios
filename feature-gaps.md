# Feature Gaps — InterlinedList iOS vs. interlinedlist.com

**Assessed:** 2026-07-18 (updated with live API probe results the same day)
**Repo:** `interlinedlist-ios` (the SwiftUI iOS client)
**Compared against:** the live web product at `https://interlinedlist.com` — its
landing page, `/help`, and `/help/api/*` detail pages — plus this repo's own
`App-Store-Deployment.md` and the actual `APIClient`/Views code, **and live
read-only probes of the production API on 2026-07-18** (test account
`messenger@interlinedlist.com`, a subscriber).

> Scope note: this is the **iOS** app. The web site lists an "iOS App (Coming
> Soon)" and a separate "macOS App (Coming Soon)"; a native macOS target does not
> exist in this repo. Everything below is about closing the iOS↔web gap.

## TL;DR

The iOS app is **close to full v1 parity** for the core product, BUT live
probing revealed **four shipped features that are currently broken** because the
client uses the wrong HTTP verb or an unsupported auth mode (Section 0). **Fix
those first** — they're regressions, not missing features. After that, the real
parity gaps are a defined set of advanced/integration features (Section 2), three
of which are **backend-blocked** because the endpoints reject Bearer tokens
(GitHub, LinkedIn targets, exports — see the companion `docs-gap.md`).

---

## Section 0 — Confirmed defects to fix first (found via live probe)

These were confirmed on 2026-07-18 by reading the production API's `OPTIONS`
`Allow` headers and by direct GETs. Each is a **client bug** (or a
backend-auth blocker) in already-shipped functionality. Verify each in-app, then
fix. Full cross-team detail is in `docs-gap.md` (F8–F13).

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| D1 | Editing profile / theme / default-visibility / avatar-from-URL silently fails | `APIClient` calls `POST /api/user/update`; server allows **only `PATCH`** (405). Also sends snake_case; server expects camelCase | Switch the three `/api/user/update` calls to `patchCamel` |
| D2 | Editing a posted message fails | `editMessage` uses `PUT /api/messages/:id`; server allows **`PATCH`, not `PUT`** (405) | Switch `editMessage` to `patchCamel` (camelCase `{content, publiclyVisible}`) |
| D3 | Marking a notification read fails | `markNotificationRead` uses `PUT /api/notifications/:id/read`; server allows **only `PATCH`** (405) | Switch to a `PATCH` request |
| D4 | CSV export always fails | `exportCSV` sends a Bearer token; `/api/exports/*` is **session-cookie-only** (401) | Backend-blocked — needs Bearer support server-side (`docs-gap.md` F1). Until then, hide the Export UI |
| D5 | Push may never arrive | `registerPushDevice` sends body `{token}`; docs specify `{deviceToken}` | Verify handler field name; likely rename `token` → `deviceToken` (`docs-gap.md` F12) |

**Prompt for Claude — fix D1/D2/D3 (verb + casing):**
> In `InterlinedList/Services/APIClient.swift`, three writes use the wrong HTTP
> method (confirmed against production via `OPTIONS` Allow headers):
> 1. `updateProfile`, `updateUserSettings`, and `applyAvatarUrl` all call
>    `post("/api/user/update", …)`. The server allows **only `PATCH`** on that
>    route and expects a **camelCase** body. Change them to use `patchCamel`
>    (add a `patchCamel` call path if needed — it already exists). Keep the
>    `{user?}`-unwrapping response handling.
> 2. `editMessage` calls `put("/api/messages/:id", …)`; the server allows
>    `PATCH` not `PUT`. Change it to `patchCamel` with a camelCase body
>    `{ content, publiclyVisible }`.
> 3. `markNotificationRead` calls `put("/api/notifications/:id/read", …)`; the
>    server allows only `PATCH`. Change it to a `PATCH` request (empty body).
> Update the corresponding `MockURLSession` unit tests to assert `PATCH` and the
> camelCase body keys. Do NOT change `patchScheduledMessage` (already correct).
> After the change, smoke-test in the simulator: edit profile, edit a message,
> mark a notification read.

**Prompt for Claude — D4 (exports) + D5 (push):**
> 1. Exports: `exportCSV` in `APIClient` sends a Bearer token, but `/api/exports/*`
>    rejects Bearer (401, confirmed live) — it's session-cookie-only. Until the
>    backend adds Bearer support (tracked in `docs-gap.md` F1 / `blocker-prompts.md`),
>    **hide the Export entry point** in the UI so users don't hit a dead feature,
>    and leave a `// TODO: re-enable when /api/exports accepts Bearer` note.
> 2. Push: `registerPushDevice`/`unregisterPushDevice` send `{ token }`; the API
>    docs specify `{ deviceToken }`. Confirm the handler field (ask backend or
>    write-test), then rename the client field to `deviceToken` if needed and add
>    a unit test asserting the body key. This is a silent-failure path (no push,
>    no error), so prioritize confirming it.

---

## Section 1 — How to read the parity gaps

Compose, feed, lists (with structured schema editing), documents (with inline
images and folders), follow graph, organizations, notifications, moderation,
push, and settings are all shipped and wired. What remains are advanced /
integration features. Each gap in Section 2 has: what the web does, iOS status,
**backend readiness (now largely confirmed by live probe)**, and a ready-to-paste
Claude prompt.

### Conventions every prompt assumes (from `CLAUDE.md`)

- **Encoders:** `get` / `postCamel` / `putCamel` / `patchCamel` for camelCase
  bodies (most endpoints); `post`/`put`/`patch` for snake_case. Check the
  existing method before adding one — mismatches fail **silently** server-side.
- **401 contract:** never log out on a feature-endpoint 401; route through
  `authState.handleUnauthorized()` (re-validates against `GET /api/user`).
- **Subscriber gating = hide, never disable/paywall.** Gate on
  `authState.user?.isSubscriber == true`. **No** billing/upgrade/price copy and
  **no** link to interlinedlist.com to pay (App Store Guideline 3.1.1).
- **Standards:** no comments unless the "why" is non-obvious; no force-unwrap;
  `@MainActor` over `DispatchQueue.main.async`; `.accessibilityLabel` on every
  control; a `#Preview` in every View file.
- **New files must be manually registered** in `project.pbxproj` (no synced
  groups) — use the `xcodeproj` Ruby gem.
- **Tests:** add `MockURLSession` unit tests for every new/changed `APIClient`
  method (assert method, path, encoder casing, decode of happy + error paths).

---

## Section 2 — Parity matrix

Legend: ✅ at parity · ◑ partial · ❌ missing · 🔴 broken · — n/a

| Web capability | iOS | Notes |
|---|---|---|
| Email/password + OAuth (Mastodon, Bluesky, LinkedIn, Twitter) | ✅ | GitHub sign-in intentionally hidden |
| Feed, link previews, dig, reply, delete, search | ✅ | |
| **Edit a posted message** | 🔴 | D2 — uses unsupported `PUT` (405) |
| Compose: image/video, scheduled, cross-post, repost, post-as-org | ✅ | |
| **Edit profile / settings / avatar-from-URL** | 🔴 | D1 — uses unsupported `POST` (405) |
| **Mark notification read** | 🔴 | D3 — uses unsupported `PUT` (405) |
| Lists: CRUD, folders, schema editor, rows, connections, watchers | ✅ | |
| Documents: CRUD, folders, search, inline images, public reader | ✅ | reads confirmed live; free-user create gate unverified (D/§2.9) |
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

---

## Section 2 — The gaps, prioritized

### Tier A — Ready to build now (backend confirmed working over Bearer)

#### 2.4 Document templates  `Small` ✅ backend-ready
**Confirmed live:** `GET /api/documents/templates` returns
`{ folderCreated, templatesFolderId, templates:[{id,title,…}] }` over Bearer
(200). Web also has `POST /api/documents/from-template` (subscriber-only) and
`POST /api/documents/templates/seed-defaults`.

**iOS status:** ❌ new documents start blank.

**Prompt for Claude:**
> Add `APIClient.documentTemplates()` returning a `[DocumentTemplate]` model
> (fields from `GET /api/documents/templates`: `id`, `title`, and content/body —
> inspect the live response for the exact keys). In the create-document flow in
> `DocumentsView`, add an optional "Start from template" picker that prefills the
> new document's title/content. If you also wire `POST /api/documents/from-template`,
> gate it on `isSubscriber` (it's a subscriber endpoint) and hide it otherwise.
> Add `MockURLSession` tests and a `#Preview`.

#### 2.5 Content deep links / universal links  `Small–Medium`
Unchanged from prior assessment. `InterlinedListApp.handleDeepLink` only routes
`reset-password`, `verify-email`, `verify-email-change`, `oauth`
(`InterlinedListApp.swift:62–74`). No content permalinks, no Universal Links.

**Prompt for Claude:**
> Extend `AppRouter` + `InterlinedListApp.handleDeepLink` to route content
> permalinks: user profiles, public lists (`/api/users/:username/lists/:id` →
> `PublicListDetailView`), public documents, and single message threads. Support
> both `interlinedlist://…` and `https://interlinedlist.com/…` via `.onOpenURL`.
> Note the confirmed public-browse namespace split: messages are
> `/api/user/:username/messages` (singular) while lists/documents are
> `/api/users/:username/…` (plural) — the wrong one 404s. Universal Links also
> need the backend to publish `apple-app-site-association` + the Associated
> Domains entitlement (capture in `blocker-prompts.md`); the custom-scheme path
> works without it. Add a share action (web permalink) on message/list/profile.

#### 2.8 Offline document sync  `Large` ✅ backend-ready (contract exists)
**Confirmed live:** `GET /api/documents/sync` returns
`{ folders:[…], … }` over Bearer (200) — the same delta-sync contract the web's
`il-sync` CLI uses. So mobile offline sync is **buildable** (not backend-blocked).

**Prompt for Claude:**
> Inspect the full `GET /api/documents/sync` and `POST /api/documents/sync`
> contracts against production (revision/`updatedAt` fields, delta vs full-body,
> conflict signals) and record in `blocker-prompts.md`. Then design (and land a
> minimal slice of) offline document editing: cache edits in `DataCache`, replay
> via the sync endpoint on reconnect, resolve conflicts last-writer-wins or with
> a simple prompt. Feature-flag it. This is large — ship the read-then-queue
> slice first, then two-way sync.

### Tier B — Backend-blocked (endpoints reject Bearer; need a backend change first)

#### 2.1 GitHub-backed lists & GitHub integration  `Large` ⛔ BACKEND (confirmed)
**What the web does:** lists are "local or **GitHub-backed**"; `/api/github/*`
covers repos, issues, labels, assignees.
**Confirmed blocker:** the GitHub docs state every `/api/github/*` endpoint
requires a **session cookie — "Bearer tokens are not accepted."** The iOS app is
Bearer-only, so **none of this is reachable** until the backend adds Bearer
support (see `docs-gap.md` Prompt A / F3). This is the biggest single parity gap.

**Prompt for Claude:**
> Do NOT build UI yet — this is backend-blocked. Confirm with the backend owner
> when `/api/github/*` will accept Bearer tokens (tracked in `docs-gap.md` F3).
> Meanwhile, produce an implementation plan only: models + `APIClient` methods for
> `GET /api/github/repos` and `GET /api/github/issues?repo=owner/repo`, a repo
> picker in `CreateListView` for GitHub-backed lists, and a read-only issues view.
> Escalate the Bearer-auth requirement as the gating dependency.

#### 2.3 LinkedIn org/target picker  `Small` ⛔ BACKEND (confirmed)
**Confirmed:** `GET /api/linkedin/posting-targets` returns **401 to Bearer**
(session-only, per docs and live probe). The `linkedInTargets` field on
`POST /api/messages` already works; we just can't fetch the target list on mobile.
We *do* have the response shape now:
`{ targets:[{ kind: personal|orgPage|personalPage, label, pageId|personalPageId,
linkedInPageId, enabled }], orgScopeMissing }`, and posting uses `pageId` /
`personalPageId` in `linkedInTargets`.

**Prompt for Claude:**
> Backend-blocked: `/api/linkedin/posting-targets` rejects Bearer. Once the
> backend adds Bearer support (`docs-gap.md` F2), add
> `APIClient.linkedInPostingTargets()` returning `[LinkedInTarget]` (kinds:
> personal/orgPage/personalPage; map `pageId`/`personalPageId` into the existing
> `linkedInTargets` request field). In `ComposeView`, when the LinkedIn toggle is
> on and the user is a subscriber, show a target picker + the existing "link as
> first comment" toggle. Hide for non-subscribers / no LinkedIn identity. Until
> Bearer works, leave the current default-destination behavior.

#### 2.2 Tag discovery / trending  `Small` ❓ needs discovery
"Hashtag organization and discovery" is marketed, but the client only supports a
`tag` filter (`messages(tag:)`), not a discovery surface. No trending-tags
endpoint is confirmed (not probed).

**Prompt for Claude:**
> Probe for a trending/known-tags endpoint against production with the E2E `.env`
> token (`GET /api/tags/trending`, `/api/tags`, `/api/messages/tags`). Record the
> real path/shape in `blocker-prompts.md`. If one exists, add
> `APIClient.trendingTags()`, a model, a "Discover" surface in `FeedView`, and make
> in-body `#hashtags` tap through to the existing `tag:` feed. If none exists,
> document as backend-blocked and stop. Tests + `#Preview`.

#### 2.7 Realtime updates  `Large` ⛔ likely BACKEND
No realtime endpoint appears in the docs and none was probed. Poll/refresh only.

**Prompt for Claude:**
> Discovery only: determine whether production exposes a realtime channel
> (`/api/stream`, `/api/events`, `/ws`, SSE `text/event-stream`). Record in
> `blocker-prompts.md`. If present, propose a `RealtimeService` (`@MainActor`,
> reconnect/backoff) that layers on the existing cache-then-refresh model. Build
> nothing until confirmed; feature-flag when built.

### Tier C — Smaller / investigate

#### 2.6 Multi-account switching  `Small`
**What the web does:** the auth docs list `GET /api/auth/accounts`,
`POST /api/auth/switch`, `POST /api/auth/remove-account` (and `?all=true` logout)
— a cached multi-account switcher. iOS is single-account.

**Prompt for Claude:**
> Confirm `GET /api/auth/accounts`, `POST /api/auth/switch`,
> `POST /api/auth/remove-account` accept Bearer (probe with the E2E token). If so,
> add an account switcher to `SettingsView`/profile: list cached accounts, switch
> active account (swap the Keychain token + `AuthState`), and remove an account.
> Keep it minimal and gated behind having >1 account. Tests + `#Preview`.

#### 2.9 Document creation gate + utility widgets  `Investigate`
- **Documents gate:** the docs mark `POST /api/documents` **subscriber-only**, but
  the iOS product direction assumes documents are free. Our probe account is a
  subscriber, so this is unverified. Test with a **non-subscriber** account: if
  creation 403s for free users, hide the create-document UI for them; if it
  succeeds, the docs are wrong (see `docs-gap.md` F13).
- **Utility widgets:** `/help/api/utility-endpoints` exists (weather, geolocation,
  image-proxy, oauth-metadata). Investigate whether weather/geolocation are
  user-facing **list column types** on the web; if so, `ListSchemaEditorView` is
  missing those column types (a real lists-parity gap). Findings only this pass.

---

## Section 3 — Housekeeping (doc drift)

Two "deferred" phases actually shipped since `App-Store-Deployment.md` was last
updated (2026-07-07):

| Phase | Doc says | Reality |
|---|---|---|
| **10 — Inline document image upload** | Tier 1, unchecked | ✅ Done (`uploadDocumentImage`; `DocumentsView.swift:692,766,785`) |
| **15 — Post as organization** | Tier 1, unchecked | ✅ Done (`postMessage(organizationId:)`; `ComposeView.swift:113`) |

**Prompt for Claude:**
> In `App-Store-Deployment.md`, move Phase 10 and Phase 15 into "What's Already
> Shipped" (2026-07-10) and update the §0 "Not yet built" line. Also add the
> Section 0 defects (D1–D5) from `feature-gaps.md` to the tracking docs as
> **bugs**, since they affect already-shipped functionality. Docs only, no code.

---

## Section 4 — Suggested execution order

1. **Section 0 defects (D1–D5)** — these are broken shipped features (profile
   edit, message edit, mark-read, export, push). Fix D1/D2/D3 immediately (one
   `APIClient` PR), confirm D5 (push field), and hide the export UI (D4) until the
   backend unblocks it. Highest priority.
2. **Backend asks** — file `docs-gap.md` Prompt A with the backend team: add
   Bearer support to `/api/exports/*`, `/api/linkedin/*`, `/api/github/*`. This
   unblocks D4 and features §2.1 and §2.3 in one move.
3. **Ready-now features** — §2.4 (document templates) and §2.5 (deep links);
   then §2.8 (offline doc sync) since its contract is confirmed Bearer-accessible.
4. **After backend unblocks Bearer** — §2.1 (GitHub-backed lists, the biggest
   parity win) and §2.3 (LinkedIn target picker).
5. **Discovery-dependent** — §2.2 (tags), §2.6 (multi-account), §2.7 (realtime),
   §2.9 (doc gate + utility widgets).

## Section 5 — Bottom line

Core product is at parity **except for four shipped features that regressed to
broken** (Section 0) — fixing those is the immediate priority and mostly a
one-file `APIClient` change. Beyond that, full web parity needs: the
backend to **accept Bearer tokens on exports/GitHub/LinkedIn** (one systemic fix
that unblocks three features), then a handful of self-contained additions
(templates, deep links, multi-account, tag discovery) and two larger systems
(offline doc sync — now confirmed buildable; realtime — still needs a backend
endpoint). See `docs-gap.md` for everything that needs the site/API team.
