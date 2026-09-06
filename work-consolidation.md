# work-consolidation.md — InterlinedList iOS: remaining parity work, consolidated

**Purpose.** The single place that answers *"what is actually left to build on iOS?"*
and *"who works on what, in parallel, without stepping on each other?"*

This doc **supersedes the open-items sections** of [`the-gaps.md`](the-gaps.md) as of
this pass. `the-gaps.md` remains the historical record of how we got here (phases 1–19,
the D1–D3 fixes, G1–G14, backend asks A1–A7). Where the two disagree, **this file wins** —
see [§7 Corrections to `the-gaps.md`](#7--corrections-to-the-gapsmd).

**Prepared:** 2026-09-05 · **Branch:** `dev` (= `main` = origin, clean tree)

---

## 1 · Method & verification (what backs every claim below)

Four sources, cross-checked, backend source as ground truth:

1. **Backend source** — `~/Codez/interlinedlist/app/api/**`, **228 route files / 296
   verb+path pairs** enumerated mechanically. Auth model read per route from the helper:
   `getCurrentUserOrSyncToken` = **Bearer or session** (mobile-OK) · `getCurrentUser`
   = **session-only** (mobile-blocked). Backend HEAD `fa1c533`.
2. **Published docs** — `docs/help/**` (19 user pages + 24 `api/*` pages), confirmed
   **live** at `https://interlinedlist.com/help/…` (spot-checked 200s on the four newest:
   `/help/ai`, `/help/api/ai-integration`, `/help/api/create-from`, `/help/api/app-settings`).
3. **Shipped iOS client** — `APIClient.swift` (151 funcs, **104 distinct verb+path pairs**
   extracted mechanically), 53 Views, 21 Models.
4. **Live read-only Bearer probes** — logged in as the `.env` test account (`messenger`,
   a **subscriber**) via `POST /api/auth/sync-token`; **GETs only, one intentional
   argument-less POST that was rejected before any write**. No mutations were performed.

### Verified baseline (this pass)

| Check | Result |
|---|---|
| Unit suite (`iPhone 16` · UDID `302E002E-…`, `-parallel-testing-enabled NO`, E2E skipped) | **823 tests, 0 failures — TEST SUCCEEDED** |
| iOS verb/path calls unsupported by the backend | **exactly 1** → [D4](#d4--avatar-changes-fail-with-405-tier-0) |
| Bearer-ready backend routes with **no iOS consumer** | **31** (excluding admin/cron/webhooks/stripe/blog/widgets/analytics/internal) |

### Live probe evidence (2026-09-05, read-only)

| Endpoint | Result | Reading |
|---|---|---|
| `GET /api/ai/status` | **200** `{"subscriber":true,"providers":["anthropic"],"defaultModels":{"anthropic":"claude-sonnet-5",…},"quota":{"usedToday":0,"dailyLimit":50,"remaining":50}}` | **AI is live in production, Bearer-ready, and included with the subscription** — `providers` comes from the app's server-side key, not the user's. iOS has zero consumers → **G15** |
| `POST /api/materialize` (empty body) | **400** `{"error":"Missing source"}` | Auth passed → "Create from…" reachable over Bearer → **G16** |
| `GET /api/lists/watching?limit=5` | **200** — real lists shared *to* the test account | Lists shared with the user are **invisible in the iOS Lists tab** → **G17** |
| `GET /api/user/adron/messages` **with vs. without** Bearer | **byte-identical responses** | The route ignores Bearer → `dugByMe` is always `false` on iOS profile walls → **A8** |
| `POST /api/user/update` | **405** | Confirms [D4](#d4--avatar-changes-fail-with-405-tier-0) |
| `GET /api/limits` | **200** `image {maxBytes 1468006, maxPixels 1200}`, `video {maxBytes 3145728}`, `message {maxContentLength 5000}` | iOS hardcodes these → **P3** |
| `GET /api/dm/conversations?take=2` | **200** `{items,nextCursor}` | Grouped inbox exists; iOS uses the flat `/api/dm` → **P2** |
| `GET /api/github/orgs` | **200** `[]` | GitHub metadata routes are reachable → **G18** |
| `GET /api/organizations/{id}/linkedin/status` | **200** `{"credential":null,"role":"member"}` | Org LinkedIn is live (flag `LINKEDIN_ORG_SCOPES_ENABLED`) → **G19** |
| `GET /api/organizations/{id}/users` | **403** "Only organization owners…" | Role gate, not auth failure → **G19** |
| `GET /api/user/app-settings/il-ios` | **404** `not_found` | Route deployed, no document yet → **G21** |
| `GET /api/users/lookup?username=…` | **400** `missing_handle` | Param is `handle`, not `username` → **P4** |

---

## 2 · Executive summary — what changed

The last full pass (`the-gaps.md`, 2026-09-05) concluded *"parity work is complete except
G11."* **That is no longer true.** The backend shipped two substantial, documented,
Bearer-ready, user-facing feature areas that iOS does not consume at all, and a third
capability (shared-in lists) turns out never to have been wired up:

1. **AI writing assistance** (`/api/ai/{status,suggest,generate}`) — five features across
   the composer, lists, and documents. Documented at `/help/ai` + `/help/api/ai-integration`.
   **iOS: nothing.** → **G15**
2. **"Create from…" / Materialize** (`POST /api/materialize`) — turn messages, lists, rows,
   or documents into a new list, document, or both. Documented at `/help/create-from` +
   `/help/api/create-from`. **iOS: nothing.** → **G16**
3. **Lists shared *with* you** (`GET /api/lists/watching`) — `GET /api/lists` is
   owner-scoped (`where: { userId: user.id }`); the web has a dedicated *"Lists you're
   watching"* tree (`components/lists/WatchedListsTreeView.tsx`). **iOS never calls it**, so
   a list shared to an iOS user is unreachable except via a share link. → **G17**

Plus one **shipped-feature defect** the D1–D3 verb-fix pass missed: **avatar changes 405**
(→ **D4**), and a tail of smaller gaps (§4) and backend asks (§6).

**Nothing previously reported as shipped has regressed** — the mechanical verb/path diff
found exactly one mismatch across all 104 iOS call sites, and the suite is green at 823.

---

## 3 · The gap list (prioritized)

### Tier 0 — broken shipped code

#### D4 — Avatar changes fail with 405 (Tier 0)

| | |
|---|---|
| **Symptom** | Setting a profile photo (camera roll **or** URL) surfaces an error in `EditProfileView`; the local `User` never refreshes. The avatar *does* land on the server, so a later app relaunch shows it — which makes this read as a flaky bug rather than a hard failure. |
| **Root cause** | `APIClient.applyAvatarUrl` (`InterlinedList/Services/APIClient.swift:246-251`) sends **`POST /api/user/update`**; the route exports **`PATCH` only** → **405** (live-confirmed). Both `uploadAvatar` (`:234`) and `setAvatarFromURL` (`:243`) funnel through it. |
| **Why it survived D1** | The D1 pass fixed `updateProfile` (`:1044`) and `updateUserSettings` (`:1059`) to `patchCamel` and missed this third call site. |
| **Correct fix** | **Delete `applyAvatarUrl`.** Both `/api/user/avatar/upload` and `/api/user/avatar/from-url` already `prisma.user.update({ data: { avatar } })` and return `{ url, user }` — decode `user` from that response (fall back to `currentUser()`), no second write needed. |
| **Also worth fixing in the same hunk** | `uploadAvatar` uses `.data(using: .utf8)!` force-unwraps ×5 (`:224-229`) — a `CLAUDE.md` "no force-unwrap in production paths" violation. |
| **Tests** | `InterlinedListTests/APIClientTests/APIClientAvatarTests.swift` currently asserts the *old* two-call shape; update it to assert a single request and a decoded `user`. |
| **Effort** | **XS** |

### Tier 1 — new, unblocked, high value

| ID | Gap | Backend | Effort |
|----|-----|---------|--------|
| **G17** ❌ | **Lists shared with me** — surface `GET /api/lists/watching` in the Lists tab (web parity: *"Lists you're watching"*). Today these lists are invisible on iOS. | 🟢 Bearer, free | **S** |
| **G15** ❌ | **AI writing assistance** — 5 features: composer *Writing Assistant* (rewrite/tighten/expand/grammar/thread/suggest-tags), *Message Series*, *Article Series*, *Powered Templates* (list create), *Powered Document* (4 modes). | 🟢 `/api/ai/{status,suggest,generate}` · 💲 **subscriber-included** (app's server-side key — no user key, no provider picker) · 50/day quota | **L** |
| **G16** ✅ | **"Create from…" (Materialize)** — message / list / rows / document → new List, Document, or both, with a preview-and-edit confirm step. **SHIPPED** — Thread C, `feat/create-from-and-github-depth`. | 🟢 `POST /api/materialize` · 💲 subscriber | **M** |

### Tier 2 — smaller systems / lower urgency

| ID | Gap | Backend | Effort |
|----|-----|---------|--------|
| **G18** ✅ | **GitHub metadata depth** — **SHIPPED** (Thread C): `githubOrgs` / `githubLabels` / `githubAssignees` / `githubNextIssueNumber`; real label + assignee pickers on GitHub-backed rows (previously hidden from the form entirely), an org filter on the repo picker, next-issue-number on list detail. **Deliberately still unconsumed:** `PATCH /api/github/issues/…` and `POST …/comments` — iOS writes issues through the `/api/lists/:id/data` proxy, which is the supported path. | 🟢 (GitHub-context auth, not the standard helper) | **M** |
| **G19** ❌ | **Organization LinkedIn management** — web has `/organizations/[slug]/linkedin`; iOS has no equivalent. `status` / `assignments` / `credential` / `sync-pages`. Behind the backend flag `LINKEDIN_ORG_SCOPES_ENABLED` — **re-verify the flag before building.** | 🟢 Bearer (owner-role gated) | **M** |
| **G21** ❌ | **Cross-device app-settings sync** — `/api/user/app-settings/{appKey}/…` (account doc + per-device docs + `bootstrap` provenance + CAS `baseVersion`, 64 KiB cap). Explicitly built for native clients (`platform: "ios"`, deviceId "kept in Keychain"). **Not a web-parity gap** — infrastructure iOS could adopt for settings continuity. | 🟢 Bearer, free | **M** |
| **G11** ❌ | **Live document presence** (collaborative cursors) — carried forward unchanged from `the-gaps.md`. Heartbeat + poll. | 🟢 `POST/DELETE /api/documents/:id/presence` | **M** |

### Papercuts (each ≤ XS, batchable into one PR)

| ID | Item | Detail |
|----|------|--------|
| **P1** | **Delete a notification** | `DELETE /api/notifications/:id` exists and is documented; iOS only has read + mark-all-read. Add a swipe action in `NotificationsView`. |
| **P2** | **Grouped DM inbox** | `GET /api/dm/conversations` returns one row per conversation (keyset cursor) — the messenger-style inbox the web uses. iOS builds its inbox from the flat `/api/dm`. Swap for correctness on high-volume threads. |
| **P3** | **Adopt `GET /api/limits`** | iOS hardcodes an image ladder starting at 2048 px; the server resizes to 1200 px / 1.4 MB regardless, so every upload wastes bytes. Read the caps at launch, cache them. (Public, no auth.) |
| **P4** | **`GET /api/users/lookup`** | Unconsumed; note the param is **`handle`**, not `username` (a `username=` query returns `400 missing_handle`). |
| **P5** | **Bluesky / Mastodon / GitHub identity status** | iOS checks only `/api/auth/{linkedin,twitter}/status`; the other three status routes exist and are unread, so `LinkedIdentitiesView` can show a stale "connected" state. |
| **P6** | **`POST /api/messages/:id/reply-counts`** | Batch reply counts — a perf win for the feed vs. per-message calls. |
| **P7** | **`GET /api/lists/:id/contributors`** | Ranked contributor list for a list (empty for GitHub-backed). No iOS consumer. |
| **P8** | **`POST /api/documents/templates/seed-defaults`** | Seeds the default template set; iOS reads `/templates` but can't seed an empty account. |

### Confirmed **not** gaps (do not build)

- **Multi-account switching** (`/api/auth/{accounts,switch,remove-account}`) — still session-only (**X1**).
- **No realtime channel** — no SSE/WS anywhere; polling is the pattern (**X3**).
- **Dashboard / front-wall layouts, engagement stats, widgets, billing/Stripe, admin, blog,
  `architecture-aggregates`** — web-only by design; billing must never ship on iOS (Guideline 3.1.1).
- **Documents shared *with* me** — the backend has no collaborator-scoped document listing, and
  the **web lacks it too**. Parity holds; it's a backend ask, not an iOS gap (see **A11**).
- **`GET /api/documents/tree`** — iOS gets the same hierarchy from the sync payload.
- **`POST /api/auth/{provider}/link`** — an alternative for clients doing their own code
  exchange. iOS's `?link=true` authorize flow is current and correct.

---

## 4 · Three parallel workstreams

Sized so three threads can run concurrently. **One rule makes this safe:**

> ⚠️ **`APIClient.swift` is the shared bottleneck** (151 funcs, one class). Three threads
> appending to it *will* conflict. **Each thread adds its endpoints in a new
> `APIClient+<Feature>.swift` extension file** (register it in `project.pbxproj` — no synced
> groups), and works in its **own git worktree**. Only Thread A edits the body of
> `APIClient.swift`; B and C treat it as read-only.

### Thread A — Defects + shared-lists parity *(this thread)*

**Deliverables**
1. **D4** — kill `applyAvatarUrl`; decode `user` from the avatar upload / from-url response; drop the five force-unwraps; rewrite `APIClientAvatarTests`.
2. **G17** — `listsWatching()` → a *"Shared with me"* section in `ListsView`, owner-vs-watcher aware (reuse the existing `list.isOwned(by:)` seam at `ListsView.swift:378`, which already anticipates shared-in lists reaching the view).
3. **P1** — `deleteNotification(id:)` + swipe-to-delete in `NotificationsView`.
4. **P3** — `serverLimits()` + cache; drive `ImageUploadProcessor` from it.
5. Owns the docs: keeps this file and `the-gaps.md` truthful as B and C land.

**Files** `APIClient.swift` (body — exclusive), `ListsView.swift`, `NotificationsView.swift`, `ImageUploadProcessor.swift`, avatar tests.
**Size** S–M · **Ship as** 3 small PRs (D4 first — it's a shipped-feature regression).

### Thread B — AI writing assistance (G15)

**Deliverables** — slice it; each slice is independently shippable:
- **B1 · Foundation** — `APIClient+AI.swift`: `aiStatus()`, `aiSuggest(...)`, `aiGenerate(...)`; `AIFeature`/`AIArtifact`/`AIQuota` models; typed error mapping for the documented codes (`subscription_required` 403, `no_provider_configured` 409, `invalid_ai_output` 422, `quota_exceeded`/`rate_limited` 429 + `Retry-After`, `provider_error` 502).
  **Gating is one flag: `aiStatus().subscriber`.** AI is **included with the subscription** — the
  provider key is the app's, held server-side. There is **no key entry, no provider picker, no
  Integrations screen, and no BYO-key state to model on iOS** (see [§5.1](#51--ai-is-a-subscriber-entitlement-not-byo-key)).
  `providers` / `defaultModels` from `/status` are **display metadata only** ("Powered by Claude
  Sonnet") — never a precondition. Subscriber ⇒ show the affordance; non-subscriber ⇒ **hide it
  silently**, no price, no upgrade copy, no link (Guideline 3.1.1).
- **B2 · Composer Writing Assistant** — pen menu in `ComposeView`: Rewrite / Tighten / Expand / Fix grammar / Split into thread / Suggest tags → suggestion sheet with *Replace draft* / *Use in draft* / *Add tags*.
- **B3 · Message Series + Article Series** — inert under 10 words (`COMPOSER_MIN_WORDS`); preview → confirm → `generate`; `scheduleImmediately` + the composer's live cross-post selection passed through as `crossPost`.
- **B4 · Powered Templates** — a tab in `CreateListView` that drafts schema + starter rows.
- **B5 · Powered Document** — `DocumentsView` button, 4 modes: Article / Derived From List / Derived From Article / Research URL.

**Contract** `/help/api/ai-integration` (live) — request/response, artifact shapes per feature, and the exact error table. Two-step **suggest → preview → confirm → generate**; both steps bill against the 50/day quota.
**Files** new `APIClient+AI.swift` + `Models/AI*.swift` + new views; touches `ComposeView`, `CreateListView`, `DocumentsView`.
**Size** L.

### Thread C — "Create from…" (G16) + GitHub depth (G18) — ✅ SHIPPED

Branch `feat/create-from-and-github-depth` (commit `bb6f64a`), **stacked on
`refactor/apiclient-transport-seam`** — the new endpoints live in `APIClient+*.swift`
files, which that refactor is what makes possible.
**Build green; 902 unit tests, 0 failures** (823 baseline + 79 new); the app launches
clean in the simulator with no runtime errors.

> **Residual verification.** The flows have **not** been driven by hand against a live
> account: the XcodeBuildMCP UI-automation tools (tap/type) aren't enabled here, and
> tapping **Create** writes real lists/documents to the shared test account. A manual
> pass over "Create from…" (all five sources) and the label/assignee pickers on a real
> GitHub-backed list is the one outstanding check.

**What landed**
- `Models/Materialize.swift` — the camelCase wire contract (`postCamel`, never `post`).
  A user-added column encodes `sourceKey` as an **explicit `null`**, not an omitted key.
- `Services/MaterializePlanner.swift` + `Services/MarkdownBlocks.swift` — pure ports of
  the backend's `build-list.ts` / `markdown-blocks.ts`, so the seeded columns and the
  preview match what the server actually builds. 56 unit tests over the pure logic.
- `Views/CreateFromSheet.swift` + `CreateFromColumnEditor.swift` — destination picker,
  column rename / retype / remove / add, live preview, created-result summary.
- `Views/SelectionActionBar.swift` — the selectable row + bottom bar the feed and list
  detail both needed (extracted rather than written twice).
- `Services/APIClient+GitHub.swift` + `Models/GitHubMetadata.swift`, plus a `multiselect`
  case in `ListItemFormView` driven by the repo's real labels and assignees.

**Two implementation decisions worth knowing**
1. **Optionless `select`/`multiselect` columns are seeded as `text`.** The server's DSL
   validator rejects a select with no `options`, and a GitHub-backed list's synthetic
   `labels`/`assignees` columns are exactly that — so "create a list from a GitHub list's
   rows" would otherwise have been a guaranteed 400.
2. **The document title is client-derived and sent explicitly.** The server derives its
   own default via `defaultDocPaths` using helpers iOS doesn't mirror; rather than guess
   at them, the sheet shows a simpler default and sends it, so what the user sees is what
   gets created. `relativePath` is still omitted, leaving the canonical path server-owned.

**Original deliverables**
1. **G16** — `APIClient+Materialize.swift`: `materialize(target:source:listConfig:docConfig:)`. Entry points mirroring the web: a message, multi-select messages, a list, list rows, a document. Shared **finalize sheet** (destination switch List / Doc / Both · list title+description+columns+public · doc title+path+public+listStyle+rowDataStyle) with a live preview, then Create. **Send id-only references** — the server re-fetches and authorizes every id and ignores client-supplied cell values. 💲 subscriber-gated.
2. **G18** — GitHub metadata: `githubOrgs()`, `githubLabels(owner:repo:)`, `githubAssignees(owner:repo:)`, `githubNextIssueNumber(...)`; label + assignee pickers on GitHub-backed list rows. **Keep the existing full-row `updateItem` write path** (`ListDetailView.setGitHubState`) — a partial `PUT` renames the issue to "Untitled".

**Contract** `/help/api/create-from` (live) — source kinds, `listConfig.fields` + `sourceKey` semantics, `docConfig`.
**Files** new `APIClient+Materialize.swift`, `APIClient+GitHub.swift`, new sheet views; touches `FeedView`, `ListsView`, `DocumentsView` for entry points.
**Size** M–L.

### Backlog (not assigned)
**G19** org LinkedIn (verify the backend flag first) · **G21** app-settings sync · **G11** document presence · **P2/P4–P8**.

### Suggested merge order
`D4` → `G17` → (B and C land independently, rebasing on `dev`) → papercuts batch.

---

## 5 · Subscriber gating (💲) — additions to the Part II map

Every new write below is subscriber-gated on the backend. **Hide the affordance for free
users; never show price or upgrade copy in-app** (App Store Guideline 3.1.1).

| Write | Gate |
|-------|------|
| `POST /api/ai/suggest`, `POST /api/ai/generate` | 💲 `403 subscription_required` (+ 50/day quota, both steps count) |
| `GET /api/ai/status` | **Free** — returns `subscriber:false`; use it to decide visibility |
| `POST /api/materialize` | 💲 mirrors the list/document create gates |
| `POST /api/documents/templates/seed-defaults` | 💲 |
| `GET /api/lists/watching`, `DELETE /api/notifications/:id`, `GET /api/limits` | **Free** ✅ |

### 5.1 · AI is a subscriber entitlement, not BYO-key

**Product decision (2026-09-05), and the deployed behavior:** a subscriber gets AI **by
default**. The provider key belongs to the app and lives server-side; the user never supplies,
sees, or manages one. This closes ask **A10** and settles G15's whole gating story.

**What this means for iOS — build these:**

- **One gate, one flag.** `aiStatus().subscriber` decides visibility for every AI affordance.
  Nothing else. Do **not** condition on `providers`, `defaultModels`, or any per-user key field.
- **Non-subscriber ⇒ the control is absent**, not disabled-with-a-pitch. No price, no "upgrade",
  no link out (Guideline 3.1.1). Same rule already applied to list/document create.
- **`providers` / `defaultModels` are display metadata.** Fine for an attribution line
  ("Powered by Claude Sonnet") or a debug row. Never a precondition.
- **Quota is the user-visible limit worth surfacing** — `quota.remaining` of `dailyLimit` 50,
  and **both** `suggest` and `generate` decrement it. Show remaining before a generate-heavy
  action; on `429 quota_exceeded` say "daily AI limit reached, resets tomorrow".

**Do NOT build:**

- ❌ Any API-key entry field, provider picker, model picker, or an Integrations-style screen.
  The web's Integrations page is **not** a parity target for AI. *(It remains the OAuth
  identity-linking surface, which iOS already covers via `LinkedIdentitiesView`.)*
- ❌ Any read of `hasOpenaiApiKey` / `hasAnthropicApiKey` / `hasGeminiApiKey` from
  `GET /api/user`. Vestigial; flagged for removal in **A10**.
- ❌ Any "add your key to enable AI" empty state.

**Error handling shifts accordingly.** `409 no_provider_configured` is no longer a
user-fixable state — it now means **the server is misconfigured or the provider is down**.
Treat it as a transient outage: hide or disable the control for the session with a neutral
"AI is unavailable right now", and **never** prompt the user to supply a key.

| Code | Status | Was (BYO) | Now (entitlement) |
|---|---|---|---|
| `subscription_required` | 403 | — | Shouldn't reach a gated UI; if it does, hide the control and refresh `/status` |
| `no_provider_configured` | 409 | "Add a key on Integrations" | **Transient server-side outage** — neutral message, no user action |
| `quota_exceeded` | 429 | Daily cap | Unchanged — surface `quota.remaining`, resets daily |
| `rate_limited` | 429 | Short-window cap | Unchanged — honor `Retry-After` |
| `invalid_ai_output` | 422 | Model returned junk | Unchanged — offer retry |
| `provider_error` | 500/502 | Upstream failure | Unchanged — offer retry |

> ⚠️ **The published docs lag the product here.** `/help/ai` and `/help/api/ai-integration`
> still say "you bring your own key". **Implement against this section and the live
> `/api/ai/status` payload, not those pages.** Doc fix tracked as **A10**.

---

## 6 · Backend / API asks

**Carried forward from `the-gaps.md`:** A1 ✅ delivered · A2 ✅ delivered (residual is the
non-code Apple-portal Associated Domains step, tracked in
`App-Store-Deployment-Checklist.md`) · A3 (Bearer multi-account — open) · A4 (doc residuals)
· A5 ✅ delivered/withdrawn · A6 (document `/api/tags/*` + `/api/link-metadata`) · **A7 ✅
delivered** — the backend now reports per-op results from `POST /api/documents/sync`
(`1eaf4b4`); the iOS `relativePath` workaround (`a7d0976`) can be simplified once the new
response shape is adopted.

**New:**

- **A8 — `GET /api/user/:username/messages` ignores Bearer.** The route resolves the viewer
  with session-only `getCurrentUser()`, so a Bearer client is anonymous. **Live-proved:**
  the response is byte-identical with and without a valid token. Consequences on iOS:
  `dugByMe` is always `false` on a profile wall (dig state flips between the feed and the
  same post on a profile), and the mutual-block filter never applies to the wall endpoint.
  **Ask:** switch to `getCurrentUserOrSyncToken`. *(One-line change; no client work needed.)*
- **A9 — Inbound email-invite acceptance is session-only.** `GET/POST /api/lists/invite/:token`
  and `/api/documents/invite/:token` use `getCurrentUser`. iOS can *send* invites
  (`ShareInvitesSheet`) but an invited iOS user cannot accept in-app — the deep link has to
  bounce to the web. **Ask:** accept Bearer on both.
- **A10 — ✅ RESOLVED (product decision, 2026-09-05): AI is a subscriber entitlement, not
  BYO-key.** Subscribers get AI by default, on the app's own server-side provider key.
  The code already reflects this (`lib/ai/resolve-provider.ts` reads server env; the route
  comment says *"AI is app-wide now, so there are no per-user keys"*; live `/api/ai/status`
  returns `providers:["anthropic"]` for an account with no keys of its own). **iOS is
  unblocked — G15 gates on `subscriber` alone.** Residual is **docs-only, non-blocking**:
  `/help/ai` and `/help/api/ai-integration` still describe "you bring your own key… added on
  the Integrations page". **Ask:** update both pages, and drop `hasOpenaiApiKey` /
  `hasAnthropicApiKey` / `hasGeminiApiKey` from `GET /api/user` if they are now vestigial.
- **A11 — No collaborator-scoped document listing.** There is a `/api/lists/watching` for
  lists but no document equivalent, so documents shared *to* a user are unlistable on
  **both** web and iOS. **Ask:** add `GET /api/documents/shared-with-me` (or extend
  `/api/documents` with a `scope=` param).
- **A13 — A GitHub-backed row can never have its labels or assignees cleared.**
  `rowDataToIssuePayload` (`lib/lists/github-list-adapter.ts`) only attaches the field
  when the parsed set is non-empty (`if (labels && labels.length > 0)`), and an empty
  string parses to nothing. So *removing* every label from an issue is unrepresentable
  from **any** client — web, iOS, or CLI — even though adding and replacing work.
  iOS now sends an explicit empty string so the intent is on the wire and a server fix
  would take effect with no client change. **Ask:** distinguish "field absent" (leave
  alone) from "field present but empty" (clear it).
- **A14 — `GET /api/github/orgs` returns two different shapes.** The deployed route
  answers a **bare array** (`[]`, live-verified); the source in `app/api/github/orgs/route.ts`
  returns `NextResponse.json(orgs)` where `orgs` is `{ orgs: OrgSummary[] }` — an
  **envelope**. iOS decodes either, but one of the two is a bug. **Ask:** pick one and
  document it. *(Note `GET /api/github/repos` returns a bare array, so the array shape
  is the consistent choice.)*
- **A12 — Document the new surfaces.** `/api/lists/watching`, `/api/lists/:id/contributors`,
  `/api/dm/conversations`, `/api/limits`, `/api/messages/:id/reply-counts`, and
  `/api/organizations/:id/users` have no `/help/api/*` page.

---

## 7 · Corrections to `the-gaps.md`

These statements in `the-gaps.md` are now **stale**; treat this file as authoritative:

| `the-gaps.md` says | Correction |
|---|---|
| *"Parity work is complete except G11 … and the bare `/lists/:id` permalink."* (2026-09-05 update) | **False.** G15 (AI), G16 (Create from…), G17 (shared lists) are open, plus D4. |
| **X4** — *"Generative AI BYO-keys … no generative endpoint in the core app, no iOS-side consumer, so defer."* | **Superseded twice over.** (a) `/api/ai/{status,suggest,generate}` are live, documented, Bearer-ready, and drive three web UIs → promoted to **G15**. (b) The BYO-key model itself is **gone**: AI ships with the subscription on the app's own key. |
| **X4 tail** — *"iOS could add key-entry fields cheaply once the D1 `PATCH` fix lands, but nothing on iOS would use them, so defer."* | **Never build this.** There are no user-supplied AI keys any more. Key-entry UI on iOS is not deferred — it is **out of scope permanently**. |
| *"`materialize` … (internal)"* under **Out of scope — web-only by design** | **Wrong.** `POST /api/materialize` backs the documented user-facing **"Create from…"** feature (`/help/create-from`). Promoted to **G16**. |
| **D1** — *"`updateProfile`/`updateUserSettings` send POST → fixed."* | **Incomplete.** A third call site (`applyAvatarUrl`) still POSTs → **D4**. |
| *"`/api/limits` — informational, not a parity gap"* | Still not a parity gap, but it is a live correctness/efficiency item → **P3**. |

---

## 8 · Appendix — Bearer-ready backend routes with no iOS consumer

Mechanically derived (296 backend verb+path pairs − 104 iOS pairs − admin/cron/webhooks/
stripe/blog/widgets/analytics/architecture/health/openapi/oauth-metadata/proxy/weather/
location/`/api/folders`). `SESSION-ONLY` rows are mobile-blocked by construction.

| Auth | Verbs | Path | Disposition |
|---|---|---|---|
| Bearer | POST | `/api/ai/generate` | **G15** |
| Bearer | GET | `/api/ai/status` | **G15** |
| Bearer | POST | `/api/ai/suggest` | **G15** |
| Bearer | POST | `/api/materialize` | **G16** |
| Bearer | GET | `/api/lists/watching` | **G17** |
| public | GET | `/api/github/orgs` | **G18** |
| public | GET | `/api/github/repos/{}/{}/assignees` | **G18** |
| public | GET | `/api/github/repos/{}/{}/labels` | **G18** |
| public | GET | `/api/github/repos/{}/{}/next-issue-number` | **G18** |
| public | PATCH | `/api/github/issues/{}/{}/{}` | **G18** (prefer the `/lists/:id/data` proxy) |
| public | POST | `/api/github/issues/{}/{}/{}/comments` | **G18** |
| Bearer | GET | `/api/organizations/{}/linkedin/status` | **G19** |
| Bearer | PUT | `/api/organizations/{}/linkedin/assignments` | **G19** |
| Bearer | DELETE | `/api/organizations/{}/linkedin/credential` | **G19** |
| Bearer | POST | `/api/organizations/{}/linkedin/sync-pages` | **G19** |
| Bearer | GET | `/api/organizations/{}/users` | **G19** (owner-gated member search) |
| Bearer | GET, PUT, DELETE | `/api/user/app-settings/{}` | **G21** |
| Bearer | GET | `/api/user/app-settings/{}/bootstrap` | **G21** |
| Bearer | GET, POST | `/api/user/app-settings/{}/devices` | **G21** |
| Bearer | PATCH, DELETE | `/api/user/app-settings/{}/devices/{}` | **G21** |
| Bearer | GET, PUT | `/api/user/app-settings/{}/devices/{}/settings` | **G21** |
| Bearer | POST, DELETE | `/api/documents/{}/presence` | **G11** |
| Bearer | DELETE | `/api/notifications/{}` | **P1** |
| Bearer | GET | `/api/dm/conversations` | **P2** |
| public | GET | `/api/limits` | **P3** |
| Bearer | GET | `/api/users/lookup` | **P4** (param is `handle`) |
| Bearer | GET | `/api/auth/bluesky/status` | **P5** |
| Bearer | GET | `/api/auth/mastodon/status` | **P5** |
| public | GET | `/api/auth/github/status` | **P5** |
| Bearer | POST | `/api/messages/{}/reply-counts` | **P6** |
| Bearer | GET | `/api/lists/{}/contributors` | **P7** |
| Bearer | POST | `/api/documents/templates/seed-defaults` | **P8** |
| Bearer | GET | `/api/documents/tree` | not a gap (sync covers it) |
| Bearer | POST | `/api/auth/{}/link` | not a gap (iOS uses `?link=true` authorize) |
| Bearer | GET | `/api/linkedin/targets` · POST `/api/linkedin/sync-pages` | low — iOS uses `posting-targets`; `sync-pages` would refresh stale pages |
| SESSION-ONLY | GET, POST | `/api/documents/invite/{}` · `/api/lists/invite/{}` | **A9** |
| SESSION-ONLY | GET | `/api/auth/accounts` · POST `/api/auth/remove-account` | **X1** |
| SESSION-ONLY | GET, PUT | `/api/user/{dashboard-layout,front-wall-layout}` · GET `/api/user/engagement` | web-only by design |

---

## 9 · Reference

- [`the-gaps.md`](the-gaps.md) — history: phases 1–19, D1–D3, G1–G14, X1–X4, A1–A7.
- [`the-gaps-access.md`](the-gaps-access.md) — access/subscription gating audit (G1–G7, all remediated).
- [`App-Store-Deployment.md`](App-Store-Deployment.md) / [`App-Store-Deployment-Checklist.md`](App-Store-Deployment-Checklist.md) — submission status; owns the residual Associated Domains portal step.
- Live contracts: `/help/api/ai-integration` · `/help/api/create-from` · `/help/api/app-settings` · `/help/ai` · `/help/create-from`.
