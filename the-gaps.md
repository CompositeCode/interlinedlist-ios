# The Gaps — InterlinedList iOS ↔ interlinedlist.com

Single source of truth for the iOS↔web feature/parity gaps and the plan to close
them. **This is a full rewrite (2026-07-31)** — the landscape changed materially
since the 2026-07-18/22 assessment (see [What changed](#what-changed-since-2026-07-22)).

**Prepared:** 2026-07-31 · **Re-verified against the live API:** 2026-08-15 (see the
[re-verification callout](#re-verification--2026-08-15-live-bearer-probe--backend-source) below)
**Method (this pass):** cross-checked four sources, with the backend source as ground truth:
1. **The backend source** at `~/Codez/interlinedlist/app/api/**` (Next.js route
   handlers — the authoritative contract). Auth model read directly from each
   route's helper: `getCurrentUserOrSyncToken` = **Bearer OR session** (mobile-OK);
   `getCurrentUser` (no sync-token) = **session-only**. Subscriber gates read from
   `isSubscriber(...)` / `forbidden("Subscribe to …")` calls.
2. **The live docs** at `https://interlinedlist.com/help/api/*` (all 21 pages,
   read 2026-07-31).
3. **The shipped iOS client** — `APIClient.swift` (78 endpoint methods) + the 41
   Views / 12 Models.
4. **Live read-only Bearer probes** (2026-07-31) with the `messenger` test account
   (`.env`, a **subscriber**): a `POST /api/auth/sync-token` login + GETs only, no
   mutations. Confirmed the source findings against production — see
   [Live evidence](#live-verification-evidence-2026-07-31). **Caveat:** `messenger`
   is a subscriber, so the **free-user gating path** (what a non-subscriber sees for
   list/doc create, media compose) is still the one thing not observable — that
   read comes from source only.

**Legend:** ✅ at parity · ◑ partial · ❌ missing · 🔴 broken · — n/a ·
🟢 backend Bearer-ready (buildable now) · ⛔ backend-blocked (session-only) ·
💲 subscriber-gated write (hide for free users, never paywall)

> **⏱ Re-verification — 2026-08-15 (live Bearer probe + backend source).** Two
> findings materially change the list below:
> 1. **A5 is DELIVERED** — `GET /api/lists` returns **`folderId`** (live-verified).
>    **Superseded same day:** iOS then **removed the list-folder concept entirely**
>    (product decision — lists organize via parent/child `parentId` nesting only).
>    `ListFolder`, `folderId`, and the `/api/folders` client calls were deleted, so the
>    delivered `folderId` field is now simply unused by iOS. See Phase 14 (reverted).
> 2. **X2 is stale — tag discovery now exists.** `/api/tags/trending` and
>    `/api/tags/autocomplete` shipped on the backend (both `getCurrentUserOrSyncToken`,
>    live-verified **200** with real data). iOS has **no consumer** → reclassified
>    from "non-feature" to a **new buildable gap (G13)**.
>
> Also new, Bearer-ready, and unconsumed on iOS: **`GET /api/link-metadata`** (live
> composer link-preview → **G14**). Everything else below is unchanged from the
> 2026-08-14 pass. Full method notes at [Part VII](#part-vii--coverage--method-notes).

---

## ▶ THE GAP LIST (prioritized)

Every open gap, most-actionable first. IDs are used throughout the plan below.

### Tier 0 — Defects in already-shipped features (fix now; one `APIClient` PR)

| ID | Gap | Root cause (source-verified) | Effort |
|----|-----|------------------------------|--------|
| **D1** 🔴 | Edit profile / settings / default-visibility silently fail | `updateProfile`/`updateUserSettings` send **POST** `/api/user/update`; route exports **only `PATCH`** → 405 | XS |
| **D2** 🔴 | Editing a posted message fails | `editMessage` sends **PUT** `/api/messages/:id`; route exports **`PATCH`** (GET/PATCH/DELETE, no PUT) → 405 | XS |
| **D3** 🔴 | Marking one notification read fails | `markNotificationRead` sends **PUT** `/api/notifications/:id/read`; route exports **only `PATCH`** → 405 | XS |

### Tier 1 — New / unblocked features, Bearer-ready, high value

| ID | Gap | Backend status | Effort |
|----|-----|----------------|--------|
| **G1** ❌ | **Direct Messages** (1:1 DMs, threads, image attach, unread badge, near-realtime) | 🟢 `/api/dm/*` (10 routes), **free** | **L** |
| **G2** ❌ | **Sharing** — tokenized share-links + document collaborators for lists & docs | 🟢 `/api/{lists,documents}/:id/share-links`, `/collaborators` · 💲 create | **M** |
| **G3** ❌ | **Document templates** — "Start from template" | 🟢 `/api/documents/templates` (free read) · 💲 `from-template` | **S** |
| **G4** ❌ | **GitHub integration** — GitHub-backed lists + issues (biggest single web feature iOS lacks) | 🟢 `/api/github/*` (**now Bearer** — was blocked) | **L** |
| **G5** ◑ | **LinkedIn posting-target picker** in the composer | 🟢 `/api/linkedin/{targets,posting-targets}` (**now Bearer** — was blocked) | **S** |
| **G6** ◑ | **People search / discovery** — find & open other users | 🟢 `/api/users/search`, `/api/users/lookup` | **S** |
| **G7** ◑ | **Muted-users management UI** (API wired, no screen) | 🟢 `/api/user/mutes` (already called) | **XS** |
| **G8** ✅◑ | **CSV Exports** — was dead (D4), backend now accepts Bearer → **verify it works** | 🟢 `/api/exports/*` (**now Bearer**) | **XS** |
| **G13** ✅ | **Tag discovery / trending** — trending-tags list + `#` autocomplete (was X2 "non-feature"; backend shipped it) | 🟢 `/api/tags/{trending,autocomplete}` (Bearer) · **✅ SHIPPED 2026-08-15** (Phase 16) | **S** |
| **G14** ✅ | **Composer live link-preview** — OG card while typing a post (read side already renders previews on *posted* messages) | 🟢 `/api/link-metadata?url=` (Bearer, rate-limited 30/60s) · **✅ SHIPPED 2026-08-15** (Phase 16) | **XS** |

### Tier 2 — Larger systems / lower urgency

| ID | Gap | Backend status | Effort |
|----|-----|----------------|--------|
| **G9** ❌ | **Offline document sync** (delta sync + full tree) | 🟢 `/api/documents/sync`, `/api/documents/tree` | **L** |
| **G10** ◑ | **Content deep links / Universal Links** (profiles, lists, docs, threads) | 🟢 client-side; ⛔ AASA needs a backend/hosting change | **M** |
| **G11** ❌ | **Live document presence** (collaborative cursors) | 🟢 `/api/documents/:id/presence` (heartbeat+poll) | **M** |
| **G12** ❌ | **Active-sessions management** (list & revoke logins) | 🟢 `/api/user/sessions`, `/api/user/sessions/:id` | **S** |

### Backend-blocked or non-existent — document, do NOT build

| ID | Item | Why it's not an iOS build |
|----|------|---------------------------|
| **X1** ⛔ | **Multi-account switching** | `/api/auth/{accounts,switch,remove-account}` are **session-cookie-only** (confirmed in source); the Bearer-only client has no cookie jar. Escalate if wanted. |
| **X2** ⚠️ | **Tag discovery / trending** | **SUPERSEDED 2026-08-15 — the backend now ships it.** `/api/tags/trending` (window day/week/month, limit ≤100) + `/api/tags/autocomplete?q=` (prefix, limit ≤50) both exist and accept Bearer (live-verified 200). No longer a non-feature → **promoted to G13**. The in-body `#hashtag` → `tag:` feed filter is the *display* side; G13 adds discovery. |
| **X3** — | **General realtime channel** | No SSE/WebSocket endpoint exists. "Realtime" is achieved by **polling**: DM `/updates` and doc `/presence`. Adopt those per-feature (G1/G11); there is nothing global to build. |

### Out of scope — web-only by design (must never ship on iOS)

Billing/Stripe (App Store Guideline 3.1.1 — no price/upgrade/pay copy or links) ·
dashboard & front-wall layout persistence · engagement stats · web widgets
(bike-share/markets/news) · admin console · `materialize` / `architecture-aggregates`
(internal) · **X4 — Generative AI BYO-keys** (OpenAI/Anthropic/Gemini keys stored
via `PATCH /api/user/update`, consumed only by the web integrations page /
`architecture-aggregates`; **no iOS-side consumer**, so defer). These are correct
absences, not gaps.

---

## Progress log (execution)

Live implementation status — updated as work lands on `dev` (uncommitted unless noted).

| Phase | Items | Status |
|---|---|---|
| **1 — correctness + quick wins** | **D1/D2/D3** verb fixes (POST/PUT→PATCH, +tests) · **G7** Muted-users screen (`MutedUsersView`, linked from Settings) · **G8** exports un-hidden + `list-data-rows` 4th type | ✅ **Done** 2026-07-31 — build green, 68 affected tests pass; also fixed 3 pre-existing stale doc-image/`folderId` tests to match backend (`file`, `folderId`) |
| **2 — Direct Messages (G1)** | `DirectMessage` models + 11 `APIClient` methods + `AppDataStore.dmUnreadCount` + envelope-badge in `MainTabView` + `MessagesInboxView` + `DMThreadView` (near-realtime `/updates` poll, image attach, block/not-mutual states) + profile "Message" button | ✅ **Done** 2026-07-31 — build green; 32 DM tests pass; ios-review fixed a duplicate-`navigationDestination` bug |
| **3 — small additions** | **G3** document templates ("Start from template", subscriber-gated, `documentTemplates()` + `createDocumentFromTemplate`) · **G6** people search (`searchUsers` + `FindPeopleView`, linked from Profile › Social) | ✅ **Done** 2026-07-31 — build green; template + search + model tests pass |
| **4 — LinkedIn target picker (G5)** | Rewrote `LinkedInTarget` to the real union `{kind,pageId?,personalPageId?}` (dropped wrong `organizationId`); `LinkedInPostingTarget` + `linkedInPostingTargets()`; multi-select in `ComposeView` (subscriber + LinkedIn identity) mapping into `linkedInTargets` on post, personal-fallback on fetch failure | ✅ **Done** 2026-07-31 — build green; 18 new tests pass |
| **5 — Sharing (G2)** | `ShareLink` + reusable `ShareLinksSheet` (create/copy/revoke, roles) for lists & documents; `DocumentCollaborator` + `DocumentCollaboratorsView` (reused `WatcherRole`); 8 `APIClient` methods wired into list + document detail | ✅ **Done** 2026-07-31 — build green; 26 sharing tests + full suite (604) pass, no regressions |
| **6 — GitHub-backed lists (G4)** | `UserList`+`source`/`githubRepo`/`githubMeta`; `GitHubRepo`/`GitHubIssue`; `githubRepos()`/`githubIssues()`/`refreshList()`/`createList(githubSource:)`; repo picker in `CreateListView` (gated on `AuthState.hasGitHubIdentity` + subscriber) + Refresh/meta on list detail | ✅ **Done** 2026-07-31 — build green; 50 tests pass. Residual: in-app GitHub *linking* still blocked (backend ask **A1**), so path verified via unit tests, not live |
| **7 — Active sessions (G12)** | `UserSession` + `userSessions()`/`revokeSession()`; `SessionsView` ("Where you're signed in") in Settings | ✅ **Done** 2026-07-31 — build green; 9 tests pass |
| **8 — Offline doc sync, Slice 1 (G9)** | `documentSync(lastSyncAt:)` delta pull + pure `DocumentSyncMerge` (upsert/tombstone) + `SyncCache` + flag-gated `AppDataStore` path (`ILOfflineDocSync`, default on); online path untouched when off. **Read-only slice** — write/push (Slice 2) + conflict-copy (Slice 3) deferred | ✅ **Done** 2026-07-31 — build green; 649-test suite passes. *(Standalone `Offline-Document-Sync-Design.md` since removed; the slice notes here + the shipped `DocumentSync*` sources are the record.)* |
| **9 — Deep links + share actions (G10)** | `ILWebURL` canonical permalinks; pure `AppDeepLink.parse` (custom-scheme + `https://interlinedlist.com`); `message(id:)` + `MessageLinkView`; "Share link" on message/profile/list/document; auth links preserved | ✅ **Done** 2026-07-31 — build green; 681-test suite passes. Inbound routing for profiles+messages; **Universal Links (https→app) still need backend AASA (ask A2)**; list/doc inbound + shared-token resolution are follow-ons |
| **10 — Offline doc sync, Slice 2 (G9)** | `SyncOperation`/outbox + coalescing (`DocumentSyncOutbox`), `pushDocumentSync` (→ `{lastSyncAt}`, 429→`rateLimited`), optimistic writes + push-then-pull `syncCycle`, `NetworkReachability` reconnect + foreground/refresh/debounced triggers, flag-branched `DocumentsView` w/ pending-sync glyph. **LWW** (per-op errors are swallowed server-side → push-then-pull reconcile); flag-off online path unchanged | ✅ **Done** 2026-08-02 — build green; 725-test suite passes (+33). **Conflict-copy is Slice 3** (seam marked `// TODO(slice 3)`) |
| **11 — Offline doc sync, Slice 3 (G9)** | **Conflict-copy** — `DocumentSyncConflict` (dirty id whose server `updatedAt` beats baseline → keep local live + preserve server version as "(conflicted copy <date>)"), `DocumentSyncMerge.apply(protectingIds:)`, **cycle reordered to pull-first-then-push** (see server's version before a local push clobbers it), baselines in `DocumentSyncState`, dismissible banner in `DocumentsView` | ✅ **Done** 2026-08-02 — build green; 747-test suite passes (+22). **G9 COMPLETE (slices 1–3).** Offline writes are no longer LWW → the default-on `ILOfflineDocSync` flag is safe; PR #13 mergeable |
| **12 — editor UX** | Markdown format toolbar (H1–H6 dropdown, icon Write/Preview) in `MarkdownEditor` | ✅ **Done** 2026-08-13 (`40b5850`) — additive; not a tracked gap |
| **13 — email share-invites (extends G2)** | `ShareInvite` model + `ShareInvitesSheet` (email-invite lists & documents by role) + watcher search | ✅ **Done** 2026-08-13 (`2ae9e20`) |
| **14 — lists into folders** | ~~`folderId` on create/update list, folder picker + move-to-folder + `RenameFolderView`; split `parentId` vs `folderId`~~ | ↩️ **Reverted 2026-08-15** — the list-folder concept was removed by product decision. Lists organize only via parent/child nesting (`parentId`); `ListFolder`, `folderId`, and the `/api/folders` client calls are gone. `ListTreeNode.buildTree(lists:)` now nests purely on `parentId` |
| **15 — API re-verification (this pass)** | Live Bearer re-probe + backend-source re-read (2026-08-15): confirmed **A5 shipped** (`folderId` in list GET), surfaced **G13** (tags trending/autocomplete now exist — was X2) and **G14** (`/api/link-metadata` composer preview). No code changes — doc-only update | ✅ **Done** 2026-08-15 |
| **16 — G13/G14 + G10 doc deep links (this session)** | **G13**: `TrendingTag`/`TagSuggestion` + `trendingTags()`/`tagAutocomplete()`; server-wide **Trending** strip & `#`-autocomplete wired into `FeedView`'s existing `tagFilter`. **G14**: `linkMetadata(url:)` + live OG preview card in `ComposeView` (`NSDataDetector` URL detection, 400 ms debounce, 429/`failed`→no card). **G10 (documents)**: `.document(id:)` + `.sharedDocument(token:)` deep links → `DocumentLinkView` / read-only `SharedDocumentView` + `resolveSharedDocument()`; parser routes `/documents/:id` and `/documents/shared/:token` (custom-scheme + https) | ✅ **Done** 2026-08-15 — app builds green; **787-test unit suite passes** (+31 new: 12 tags, 9 link-metadata, 6 resolver, +4 parse) |
| — | **iOS-only tail of A1/A2** — merge staged `feat/github-oauth-universal-links` (1 commit ahead of `dev`: flips GitHub `supportsNativeAuth→true` + Associated Domains entitlement); enable the Apple-portal Associated Domains capability & regen profile · **G10 list follow-ons** *(list **share-token** inbound now shipped — `/lists/shared/:token` routes to a read-only `SharedListView` via `resolveSharedList()`/`sharedListData()`; bare `/lists/:id` permalink inbound remains **backend-limited** — no owner username in the URL)* · **G11 presence** *(optional)* | ⏳ remaining |

**Whole-tree gate (2026-07-31, after the fix pass):** full unit suite **694 tests,
0 failures** (E2E excluded). All work builds and passes together; Phases 1–9
committed as clean per-feature commits (`APIClient.swift` hunk-split per phase;
`project.pbxproj` registration consolidated in one `build:` commit), G9 Slice 1 and
G10 each their own commit, plus a fix commit.

**Interactive smoke-test (2026-07-31):** logged in as `@messenger` (subscriber) and
exercised all new surfaces. **6/7 PASS** (DM inbox, people search, sessions, muted
users, share actions, GitHub-list gating, document sharing — no crashes). Two real
defects found and **fixed**: **D-1** DM new-message recipient tap didn't open the
thread (fragile `onChange`-after-dismiss nav → now `navigationDestination(item:)` +
full-width tappable row, matching the verified-good `FindPeopleView` pattern);
**D-2** (pre-existing) `FollowStatus` decode mismatch — API returns
`{status,isFollowing,isPending}`, client wanted `{following,followedBy,pendingRequest}`
→ remapped defensively (also fixed the latent nested `follow.status` shape on
`POST /api/follow/:id`). Plus a resource-aware share-copy nit. **D-1's literal
runtime tap wasn't re-driven** — the UI-automation tooling wasn't available in the
re-check session — but the fix mirrors the interactively-confirmed people-search
flow and is unit-/build-verified; a manual tap-test is the one residual check.

**Shipped this session (parity closed):** defects **D1/D2/D3** · **G1** Direct
Messages · **G2** Sharing · **G3** Templates · **G4** GitHub-backed lists · **G5**
LinkedIn target picker · **G6** People search · **G7** Muted-users UI · **G8**
Exports (verified live) · **G12** Active sessions. **Remaining:** G9 (needs design),
G10 (needs backend AASA), G11 (optional), + backend asks **A1** (GitHub mobile
linking) and **A2** (Universal-Links AASA).

**Note on sequencing:** `APIClient.swift` (one 69 KB class) is the shared bottleneck —
every remaining feature appends methods to it, so feature agents are **serialized**
(one cohesive feature per agent, build verified between each) rather than run in
parallel, to avoid clobbering that file.

---

## What changed since 2026-07-22

The prior doc's headline finding — *"exports, GitHub, and LinkedIn reject Bearer,
so they're unreachable from mobile"* — is **fully resolved**. The backend team
shipped the old "Prompt A." Source-verified today: every one of those areas now
authenticates through `getCurrentUserOrSyncToken` (Bearer or session).

| Old item | Then | Now (source-verified 2026-07-31) |
|----------|------|-----------------------------------|
| D4 / F1 — CSV exports reject Bearer | 🔴 dead | ✅ **Bearer accepted** — all 4 `/api/exports/*` use `getCurrentUserOrSyncToken`. iOS already sends Bearer → **should work**; just verify (G8). |
| §2.1 / F3 — GitHub rejects Bearer | ⛔ blocked | 🟢 **Bearer accepted** — `getGitHubIssuesContext` resolves the user via `getCurrentUserOrSyncToken`. Now buildable (G4). |
| §2.3 / F2 — LinkedIn targets reject Bearer | ⛔ blocked | 🟢 **Bearer accepted** — `/api/linkedin/{targets,posting-targets,sync-pages}`. Now buildable (G5). |
| D5 / F12 — push field `token` vs `deviceToken` | ⚠️ verify | ✅ **Non-issue** — docs + handler use `token`; iOS already sends `token`. Closed. |
| F5 — no Moderation docs | ❌ missing | ✅ `/help/api/moderation` now exists; endpoints Bearer-accepted; iOS already ships block/mute/report. At parity. |
| §2.9 — weather/geo as list column types? | ❓ | ✅ **No** — `/api/weather`, `/api/location`, `/api/widgets/*` are backend data helpers, not list column types. Not a lists gap. |
| F13 — is document create subscriber-only? | ⚠️ verify | ✅ **Confirmed subscriber-only** — `POST /api/documents` → `forbidden("Subscribe to create documents.")`. Hide create for free users (💲). |
| §2.6 — do multi-account routes take Bearer? | ❓ | ⛔ **No** — session-only (X1). Reclassified from "investigate" to backend-blocked. |
| §2.2 — probe for a trending endpoint | ❓ | ~~None exists (X2)~~ → **Now exists (2026-08-15):** `/api/tags/{trending,autocomplete}` shipped, Bearer-accepted, live-verified 200. Promoted to **G13**. |

And three genuinely **new** feature areas shipped on the backend since the last
pass, all Bearer-ready: **Direct Messages** (G1), **Sharing/share-links** (G2),
and **document collaborators / templates / sync / presence** (G2/G3/G9/G11).

**Net:** the parity story flipped from *"blocked on the backend"* to *"a stack of
self-contained iOS builds we can do today."* Three tiny verb fixes are the only
regressions left in shipped code.

---

## Live-verification evidence (2026-07-31)

Read-only Bearer probes with `messenger` (subscriber) against production. Every
new/unblocked area returned exactly what the source predicted — a **401 would mean
Bearer rejected**; none did.

| Gap | Endpoint (GET) | Live result | Reading |
|---|---|---|---|
| **G8** | `/api/exports/{messages,lists,list-data-rows,follows}` | **200** — real CSV rows | Exports **work over Bearer** (old D4 blocker gone) |
| **G1** | `/api/dm` · `/api/dm/unread-count` · `/api/dm/recipients` | **200** `{items:[]}` · `{count:0}` · `{recipients:[…]}` | DMs live; `/recipients` returns the mutual-follow set |
| **G1** | `/api/dm/thread/adron` | **200** `{items:[], olderCursor, isMutual:true, isBlocked:false, otherUser:{…}}` | Exact thread shape confirmed |
| **G3** | `/api/documents/templates` | **200** `{folderCreated, templatesFolderId, templates:[…]}` | Real templates returned |
| **G9** | `/api/documents/sync` | **200** `{folders, documents, lastSyncAt}`; folder rows carry `deletedAt` | Real delta-sync contract (`lastSyncAt` cursor + tombstones) |
| **G9** | `/api/documents/tree` | **200** nested `{folders:[{…, documents:[…]}]}` | One-call hierarchy |
| **G5** | `/api/linkedin/{posting-targets,targets}` | **200** `{targets:[{kind:"personal", label, avatarUrl, …}]}` | LinkedIn targets **work over Bearer** (old F2 blocker gone) |
| **G4** | `/api/github/repos` | **400** `"GitHub account not linked"` (NOT 401) | Bearer **auth passes**; only identity-linking remains (ask A1) |
| **G6** | `/api/users/search?q=…` | **200** `{users:[…]}` | People search works (note: `/users/lookup` wants a different param than `username=`) |
| **G12** | `/api/user/sessions` | **200** `{sessions:[{deviceLabel:"CLI", isCurrent, lastUsedAt, …}]}` | Session list/revoke live |
| **G2** | `/api/lists/:id/share-links` · `/api/documents/:id/{share-links,collaborators}` | **200** `{shareLinks:[]}` · `{collaborators:[], pagination}` | Owner reads work over Bearer |

**Two things surfaced by the live `GET /api/user` that the source scan hadn't:**
- **`githubDefaultRepo`** — a user setting (validated `owner/repo`) for the default
  repo of GitHub-backed lists. Belongs with **G4**; expose it in the GitHub-list UI.
- **`hasOpenaiApiKey` / `hasAnthropicApiKey` / `hasGeminiApiKey`** — a **"Generative
  AI" BYO-key** feature (web `Settings › GenerativeAISection`, keys set via
  `PATCH /api/user/update`). The keys are consumed **only** by the web
  `integrations` page and the internal `architecture-aggregates` tooling — there is
  **no generative endpoint in the core app**. So it's a **web-only integrations
  feature with no iOS-side consumer** → **out of scope** (X4), not a parity gap. iOS
  could add key-entry fields cheaply once the D1 `PATCH /api/user/update` fix lands,
  but nothing on iOS would use them, so defer.

---

## Part I — Conventions every iOS prompt assumes (from `CLAUDE.md`)

- **Encoders:** `get` / `postCamel` / `putCamel` / `patchCamel` for camelCase
  bodies (most endpoints); `post`/`put`/`patch` for snake_case. Check the existing
  method before adding one — mismatches fail **silently** server-side.
- **401 contract:** never log out on a feature-endpoint 401; route through
  `authState.handleUnauthorized()` (re-validates against `GET /api/user`).
- **Subscriber gating = HIDE, never disable/paywall.** Gate on
  `authState.user?.isSubscriber == true`. **No** billing/upgrade/price copy and
  **no** link to interlinedlist.com to pay (Guideline 3.1.1). When a write 💲-gate
  fires anyway (403 `"Subscribe to …"`), fail gracefully — don't surface the raw
  server string as a paywall.
- **Standards:** no comments unless the "why" is non-obvious; no force-unwrap;
  `@MainActor` over `DispatchQueue.main.async`; `.accessibilityLabel` on every
  control; a `#Preview` in every View file.
- **New files must be registered** in `project.pbxproj` (no synced groups) — use
  the `xcodeproj` Ruby gem.
- **Tests:** add `MockURLSession` unit tests for every new/changed `APIClient`
  method (assert method, path, encoder casing, decode of happy + error paths).
- **Public-browse namespace split is real and load-bearing** — do NOT normalize:
  messages are `/api/user/:username/messages` (singular `user`); lists & documents
  are `/api/users/:username/…` (plural). The wrong one 404s.

---

## Part II — Confirmed 💲 subscriber-gated writes (gating map)

Same backend for web and iOS, so these aren't parity *gaps* — but every new/edited
iOS write below must respect them (hide the affordance for non-subscribers). Read
directly from source:

| Write | Gate |
|-------|------|
| `POST /api/messages` (plain text) | **Free** ✅ |
| `POST /api/messages` **with images / video / cross-post / schedule** | 💲 `"Subscribe to unlock images, video, cross-posting, and scheduled posts."` |
| `POST /api/lists` (create list) | 💲 `"Subscribe to create lists."` |
| `POST /api/documents` (create doc) | 💲 `"Subscribe to create documents."` |
| `POST /api/documents/from-template`, `…/templates/seed-defaults` | 💲 |
| `POST /api/{lists,documents}/:id/share-links` (create link) | 💲 |
| `POST/PUT /api/documents/:id/collaborators*`, `POST/PUT /api/lists/:id/watchers*` | 💲 |
| `POST /api/organizations` (create org) | 💲 |
| Revoke share-link (`DELETE …/share-links/:token`), DM send, templates read | **Free** ✅ |

> **Action item (gating audit):** verify the shipped composer already hides
> image/video/cross-post/schedule affordances for non-subscribers, and that
> `CreateListView` / document-create are hidden for free users. If not, that's a
> Guideline 3.1.1 risk to fix alongside Tier 0.

---

## Part III — Parity matrix (current)

| Web capability | iOS | Notes |
|---|---|---|
| Email/password + OAuth (Mastodon, Bluesky, LinkedIn, X) | ✅ | GitHub sign-in still hidden (see G4) |
| Feed: previews, dig, reply, delete, search, scheduled, cross-post, post-as-org | ✅ | |
| **Edit a posted message** | 🔴 | **D2** — client sends unsupported `PUT` |
| **Edit profile / settings** | 🔴 | **D1** — client sends unsupported `POST` |
| **Mark one notification read** | 🔴 | **D3** — client sends unsupported `PUT` |
| Lists: CRUD, schema DSL, rows, connections, watchers, parent/child nesting | ✅ | list create is 💲; **list folders removed 2026-08-15** — lists nest via `parentId` only |
| Documents: CRUD, folders, search, inline images, public reader | ✅ | doc create is 💲 (confirmed) |
| **Document templates** | ❌ | **G3** — Bearer-ready |
| **Document collaborators / share-links** | ❌ | **G2** — iOS has list *watchers* only |
| **List / document tokenized share-links** | ❌ | **G2** |
| Follow graph, orgs, notifications, moderation (block/mute/report), push | ✅ | mute has no list UI (**G7**) |
| **CSV exports** | ◑ | **G8** — wired; was dead (Bearer), now unblocked — verify |
| **Direct Messages** | ❌ | **G1** — entirely absent |
| **People search / discovery** | ◑ | **G6** — only list-scoped user search exists |
| **GitHub-backed lists / issues** | ❌ | **G4** — now Bearer-ready |
| **LinkedIn org/target picker** | ◑ | **G5** — `linkedInTargets` posts; can't fetch targets yet |
| **Offline document sync** | ❌ | **G9** |
| **Content deep / universal links** | ◑ | **G10** — profile/message/**document**/**doc-share-token**/**list-share-token** routed; bare list permalinks backend-limited (no owner in URL); Universal Links pending A2 iOS merge |
| **Live doc presence (cursors)** | ❌ | **G11** |
| **Active-sessions management** | ❌ | **G12** |
| Multi-account switching | ⛔ | **X1** — session-only backend |
| **Tag discovery / trending** | ✅ | **G13** — trending strip + `#` autocomplete in FeedView (Phase 16) |
| **Composer live link-preview** | ✅ | **G14** — live OG card in ComposeView (Phase 16) |
| Realtime channel (SSE/WS) | — | **X3** — none; polling only |
| Billing, layouts, engagement, widgets, admin | — | web-only by design |

---

## Part IV — Implementation plan

Ordered to match the gap list. Each item lists the **endpoints + auth + gating**,
the **models / `APIClient` methods** to add, the **UI**, and a **ready-to-paste
prompt**. All new `APIClient` methods use `Bearer` and the camelCase helpers unless
noted, and every one needs `MockURLSession` tests + a `#Preview`.

### Tier 0 — Defect fixes (do first)

All three are verb mismatches confirmed against the route handlers today
(`/api/user/update` → PATCH-only; `/api/messages/:id` → GET/PATCH/DELETE, no PUT;
`/api/notifications/:id/read` → PATCH-only).

> **Prompt — fix D1/D2/D3 (one PR):**
> In `InterlinedList/Services/APIClient.swift`:
> 1. `updateProfile` and `updateUserSettings` call `post("/api/user/update", …)`.
>    The route exports **only `PATCH`** and expects a **camelCase** body. Switch
>    both to `patchCamel`. Keep the `{user?}`-unwrap.
> 2. `editMessage` calls `put("/api/messages/:id", …)`; the route has no `PUT`
>    (GET/PATCH/DELETE only). Switch to `patchCamel` with `{ content,
>    publiclyVisible }`.
> 3. `markNotificationRead` calls `put("/api/notifications/:id/read", …)`; route is
>    `PATCH`-only. Switch to a `PATCH` (empty body).
> Update `MockURLSession` tests to assert `PATCH` + camelCase keys. Do NOT touch
> `patchScheduledMessage` (already correct) or `updateNotificationPreference`
> (already `PATCH`). Smoke-test in the sim: edit profile, edit a message, mark one
> notification read.

**Closed (no work):** D4 exports now accept Bearer (→ verify under **G8**); D5 push
field is `token` and already matches.

---

### Tier 1

#### G1 — Direct Messages `Large` 🟢 free, top priority

The largest single missing surface, fully Bearer-ready and free. Contract
(`getCurrentUserOrSyncToken` on every route; participants must **mutually follow**
and neither may block the other):

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/dm?folder=inbox\|sent\|deleted&cursor=` | List a DM folder (cursor paginated) |
| POST | `/api/dm` | Send `{ recipientId, body(1–10000), imageUrls[] }` → `{ message }` |
| GET | `/api/dm/:id` | Fetch one message |
| POST | `/api/dm/:id/read` | Mark received message read (recipient only) → `{ updated }` |
| POST | `/api/dm/:id/trash` · `/restore` | Soft-delete / undo (per-side) → `{ ok }` |
| GET | `/api/dm/recipients` | Users you may DM (mutual-follow set) |
| GET | `/api/dm/thread/:username` | Full conversation (`items`, `olderCursor`, `isMutual`, `isBlocked`, `otherUser`) |
| GET | `/api/dm/thread/:username/updates?after=:msgId` | **Incremental poll** — new messages only; auto-marks read |
| GET | `/api/dm/unread-count` | `{ count }` for a tab badge |
| POST | `/api/dm/images/upload` | multipart `file` → `{ url }` (verified-email-gated, not 💲) |

Error contract to surface gracefully: 400 `self_message`/`invalid_body`, 404
`recipient_not_found`, 403 `blocked` / `not_mutual`.

- **Models:** `DirectMessage`, `DMThread`, `DMFolder`, `DMRecipient`, `DMUnreadCount`.
- **APIClient:** `directMessages(folder:cursor:)`, `sendDirectMessage(recipientId:body:imageUrls:)`,
  `dmThread(username:)`, `dmThreadUpdates(username:after:)`, `markDMRead(id:)`,
  `trashDM(id:)`, `restoreDM(id:)`, `dmRecipients()`, `dmUnreadCount()`,
  `uploadDMImage(_:)`.
- **UI:** new `MessagesInboxView` (a fifth tab or a Profile entry), `DMThreadView`
  (chat bubbles, markdown, image attach), a compose-DM flow seeded from
  `/recipients` or from a profile's "Message" button. Add a DM unread badge
  (poll `/unread-count`; refresh on tab focus + `AppDataStore` prefetch). While a
  thread is open, poll `/updates?after=<lastId>` on a `@MainActor` timer (~3–5 s,
  backoff when backgrounded) — this is the "near-realtime" story (no WS to build).
- **Add a "Message" affordance** on `UserProfileView` when `isMutual`.

> **Prompt — Direct Messages (ship in slices):** Slice 1 read-only: models +
> `dmThread`/`directMessages`/`dmUnreadCount`, an inbox list, a read-only thread,
> and an unread badge. Slice 2: `sendDirectMessage` + composer + `/updates`
> polling. Slice 3: image attach (`uploadDMImage`), trash/restore, and the
> profile "Message" button gated on `isMutual`. Handle the 403 `not_mutual` /
> `blocked` states with clear empty-state copy, never a crash. Tests for every
> `APIClient` method; `#Preview` per view.

#### G2 — Sharing: share-links + document collaborators `Medium` 🟢 (💲 create)

iOS ships per-person **list watchers** but nothing for **document collaborators**
or **tokenized share-links** on either resource. Roles are uniform:
`watcher`(Viewer) / `collaborator`(Editor) / `manager`(Admin). Only the **owner**
may create/list/revoke links.

| Method | Path | Auth | Gate |
|---|---|---|---|
| GET/POST | `/api/lists/:id/share-links` | Bearer | POST 💲 |
| DELETE | `/api/lists/:id/share-links/:token` | Bearer | free |
| GET/POST | `/api/documents/:id/share-links` | Bearer | POST 💲 |
| DELETE | `/api/documents/:id/share-links/:token` | Bearer | free |
| GET/POST/PUT/DELETE | `/api/documents/:id/collaborators[/:userId]` | Bearer | write 💲 |
| GET | `/api/documents/:id/collaborators/users` | Bearer | free (candidate search) |
| GET | `/api/{lists,documents}/shared/:token[/data]` | optional | anon read (resolver) |

- **Models:** `ShareLink { token, role, url, expiresAt, createdAt, revokedAt }`,
  `DocumentCollaborator`, reuse `WatcherRole`.
- **APIClient:** `listShareLinks(kind:id:)`, `createShareLink(kind:id:role:expiresAt:)`,
  `revokeShareLink(kind:id:token:)`; `documentCollaborators(id:)`,
  `addDocumentCollaborator(id:userId:role:)`, `setDocumentCollaboratorRole(...)`,
  `removeDocumentCollaborator(...)`, `searchDocumentCollaboratorCandidates(id:q:)`.
- **UI:** a reusable `ShareSheet` (create link at a role, copy `url`, revoke) hung
  off list detail and document detail; a `DocumentCollaboratorsView` mirroring
  `WatchersListView`. Create actions hidden for non-subscribers; revoke stays.
- **Also handle inbound links** in G10 (`/shared/:token` resolver → read-only
  view + "Claim" when signed in; claim is **session-only**, so on iOS a claimed
  Editor/Admin link may need the web — note that limitation in the UI).

> **Prompt — Sharing:** Add the share-link `APIClient` methods + `ShareLink` model
> and a `ShareSheet` for lists and documents (create/copy/revoke, roles). Add
> `DocumentCollaboratorsView` modeled on `WatchersListView`. Gate create/modify on
> `isSubscriber` (hide, don't paywall). Tests + previews.

#### G3 — Document templates `Small` 🟢 (read free, create 💲)

`GET /api/documents/templates` → `{ folderCreated, templatesFolderId,
templates:[{id,title,…}] }` (free). `POST /api/documents/from-template` (💲)
creates from one; `POST /api/documents/templates/seed-defaults` (💲) seeds the set.

- **Model:** `DocumentTemplate`. **APIClient:** `documentTemplates()`,
  `createDocumentFromTemplate(templateId:…)`, `seedDefaultTemplates()`.
- **UI:** in the create-document flow, an optional "Start from template" picker
  that prefills title/content; call `from-template` when chosen (hidden for free
  users, since create itself is 💲).

#### G4 — GitHub integration `Large` 🟢 **now unblocked**

Was the single biggest backend-blocked gap; `/api/github/*` now authenticates via
`getGitHubIssuesContext` → `getCurrentUserOrSyncToken` (**Bearer OK**), requiring a
**linked GitHub identity**.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/github/repos` | Repos for the linked account |
| GET/POST | `/api/github/issues?repo=owner/repo` | List / create issues |
| PATCH | `/api/github/issues/:owner/:repo/:number` | Edit labels/assignees |
| POST | `/api/github/issues/:owner/:repo/:number/comments` | Comment |
| GET | `/api/github/repos/:owner/:repo/{assignees,labels,next-issue-number}` | Metadata |

**Live-confirmed:** `GET /api/github/repos` over Bearer returned **400 "GitHub
account not linked"** (not 401) — i.e. Bearer auth *passes*; the endpoint only
lacked a linked identity on the test account.

Two sub-gaps: (a) **GitHub OAuth sign-in is still hidden** on iOS because the web
GitHub callback sets a cookie and redirects to `/dashboard` (no custom-scheme
handoff) — linking a GitHub identity from mobile still needs a backend mobile
branch on the callback, so **identity-linking remains blocked even though the data
endpoints are open**. (b) Once an identity is linked (e.g. via web), the data
endpoints work over Bearer.

- **Plan:** build models (`GitHubRepo`, `GitHubIssue`, `GitHubLabel`,
  `GitHubAssignee`) + `APIClient` methods; add a **repo picker in `CreateListView`**
  for GitHub-backed lists and an **editable issues view** (add issues; edit
  title/body/state; one-tap Close/Reopen — the standard `/api/lists/:id/data`
  routes proxy create→issue, PUT→patch, DELETE→close); create-issue-from-message.
  Surface the **`githubDefaultRepo`** user setting (from `GET /api/user`, set via
  the D1-fixed `PATCH /api/user/update`, validated `owner/repo`) as the default in
  that picker. Guard the whole surface on "has a linked GitHub identity" (from
  `/api/user/identities`) and show an explainer when absent.
- **Escalate to backend:** add a mobile branch to `/auth/github/callback` (custom
  scheme + `?token=`) so iOS users can *link* GitHub without the web — the last
  remaining GitHub blocker.

#### G5 — LinkedIn posting-target picker `Small` 🟢 **now unblocked**

`GET /api/linkedin/posting-targets` (Bearer, **live-confirmed 200** with real
targets, e.g. `{ kind:"personal", label:"Adron Hall", avatarUrl, … }`) →
`{ targets:[{ kind: personal|orgPage|personalPage, label, pageId|personalPageId,
linkedInPageId, enabled }], orgScopeMissing }`. `PUT` updates prefs; `POST
/sync-pages` refreshes.
The composer's `linkedInTargets` field already posts correctly — iOS just couldn't
*fetch* the list before.

- **APIClient:** `linkedInPostingTargets()`, `updateLinkedInTargets(_:)`,
  `syncLinkedInPages()`. **Model:** `LinkedInTarget`.
- **UI:** in `ComposeView`, when the LinkedIn cross-post toggle is on and the user
  is a subscriber with a LinkedIn identity, show a target picker (map
  `pageId`/`personalPageId` into `linkedInTargets`) + the existing "link as first
  comment" toggle. Hide otherwise.

#### G6 — People search / discovery `Small` 🟢

Backend has `GET /api/users/search?q=` and `GET /api/users/lookup?username=`
(Bearer). iOS only has *list-scoped* user search (`searchWatcherCandidates`) — no
way to find or open an arbitrary user. Add `searchUsers(q:)` + a search field that
routes results into `UserProfileView`. Small but high-utility (currently you can
only reach a profile via the feed).

#### G7 — Muted-users management UI `XS` 🟢

`mutedUsers()` / `muteUser()` / `unmuteUser()` are already wired; only a screen is
missing. Add `MutedUsersView` mirroring `BlockedUsersView` and link it from
`SettingsView` next to Blocked Users.

#### G8 — Verify CSV exports now work `XS` 🟢

`exportCSV` already sends Bearer; the four `/api/exports/*` routes now accept it —
**live-confirmed 200 with real CSV** for all four (`messages`, `lists`,
`list-data-rows`, `follows`) on 2026-07-31. **Un-hide the export entry point** (if
it was hidden per the old D4 plan), remove any `// TODO: re-enable when …` note, and
smoke-test in-app. Note the client knows only 3 of 4 — add `list-data-rows`.

#### G13 — Tag discovery / trending `Small` 🟢 ✅ SHIPPED 2026-08-15 (Phase 16)

Backend shipped two Bearer endpoints (both `getCurrentUserOrSyncToken`), **live-verified 2026-08-15**:

| Method | Path | Shape |
|---|---|---|
| GET | `/api/tags/trending?window=day\|week\|month&limit=` (default week, ≤100) | `{ tags:[{ tag, count, lastUsedAt }] }` |
| GET | `/api/tags/autocomplete?q=<prefix>&limit=` (≤50; leading `#` stripped; `q` required) | `{ tags:[{ tag, count }] }` |

Both scope to **public** messages only. iOS already filters the feed by `tag:` in-body,
but has no discovery surface.

- **Models:** `TrendingTag { tag, count, lastUsedAt }`, `TagSuggestion { tag, count }`.
- **APIClient:** `trendingTags(window:limit:)`, `tagAutocomplete(q:limit:)` (plain `get`,
  camelCase decode). `MockURLSession` tests for both + the 400 empty-`q` path.
- **UI:** a trending-tags strip/section (e.g. on the feed or a discovery screen) whose
  taps drive the existing `tag:` feed filter; `#`-autocomplete suggestions in the
  compose field and/or the feed search box. All read-only, **free** — no gating.

#### G14 — Composer live link-preview `XS` 🟢 ✅ SHIPPED 2026-08-15 (Phase 16)

`GET /api/link-metadata?url=<http(s) url>` (Bearer; rate-limited 30/60 s → 429 with
`Retry-After`) returns a terminal `{ link: LinkMetadataItem }` (OG title/description/
image, `fetchStatus: success|failed`) so the composer can render a WYSIWYG preview
**before** posting. iOS already decodes `LinkMetadataItem` and renders previews on
*posted* messages (`LinkPreviewBlock` in `MessageDetailView`) — this only adds the
**compose-time** card.

- **APIClient:** `linkMetadata(url:)` (debounce on the caller side; treat 429/`failed`
  as "no card", never a hard error).
- **UI:** in `ComposeView`, detect the first URL as the user types and show a compact
  preview card (or its placeholder on `failed`). Free; no gating.

---

### Tier 2

#### G9 — Offline document sync `Large` 🟢

`GET/POST /api/documents/sync` is a delta-sync contract (Bearer; emits
`RateLimit-*` headers; `lastSyncAt` param) and `GET /api/documents/tree` returns
the full hierarchy in one call. **Live-confirmed shape:** `GET /sync` →
`{ folders, documents, lastSyncAt }`, folder/doc rows carrying `createdAt`,
`updatedAt`, and **`deletedAt`** (soft-delete tombstones) — so `lastSyncAt` is the
delta cursor and deletions replicate cleanly; `tree` → nested
`{ folders:[{ …, documents:[…] }] }`. Plan: (1) confirm the `POST /sync` write
contract (conflict signals) against production; (2) cache doc edits in `DataCache`,
replay via `POST /sync` on reconnect,
resolve last-writer-wins with a simple conflict prompt; (3) feature-flag it and
ship read-then-queue first, two-way second. `documents/tree` is a cheap early win
(fewer round-trips building the folder tree).

#### G10 — Content deep links / Universal Links `Medium`

`InterlinedListApp.handleDeepLink` routes only `reset-password`, `verify-email`,
`verify-email-change`, `oauth`. Extend `AppRouter` + `.onOpenURL` to route content
permalinks: profiles, public lists (`/api/users/:username/lists/:id` →
`PublicListDetailView`), public documents, message threads, **and inbound
share-links** (`/{lists,documents}/shared/:token` → read-only resolver view from
G2). Support both `interlinedlist://…` and `https://interlinedlist.com/…`. Add a
"Share" action (web permalink) on message/list/doc/profile.
**Backend dependency:** Universal Links need the site to publish
`apple-app-site-association` + the Associated Domains entitlement — file that ask;
the custom-scheme path works without it. Share-link **claim** is session-only, so
Editor/Admin claims may still require web (note in UI).

#### G11 — Live document presence `Medium` (optional)

`POST/DELETE /api/documents/:id/presence` is a heartbeat+poll cursor-sync (no WS).
Low urgency for a phone; consider a lightweight "N people viewing" indicator before
full collaborative cursors. Build only after G2/G9.

#### G12 — Active-sessions management `Small` 🟢

`GET /api/user/sessions` (list web+mobile logins) + `DELETE /api/user/sessions/:id`
(revoke). A security-hygiene screen in `SettingsView` ("Where you're signed in" →
revoke). Nice-to-have; pairs well with account-security UI.

---

## Part V — Suggested execution order

1. **Tier 0 (D1–D3)** — one `APIClient` PR; broken shipped features. Same PR: run
   the **gating audit** (Part II) so no 💲 write is exposed to free users.
2. **G8 exports verify** + **G7 muted-users UI** — near-zero-effort wins that close
   two matrix rows immediately.
3. **G1 Direct Messages** — biggest new surface; ship in 3 slices (read → send →
   attach/trash). Highest user-visible parity gain.
4. **G3 templates**, **G5 LinkedIn picker**, **G6 people search** — small,
   self-contained, independently shippable.
5. **G2 Sharing** — share-links + document collaborators (pairs with G10 inbound).
6. **G4 GitHub** — big win; data endpoints are ready now. File the
   `/auth/github/callback` mobile-branch ask in parallel (identity-linking blocker).
7. **G9 offline sync**, **G10 deep/universal links**, **G12 sessions**,
   **G11 presence** — larger/infra, lower urgency.
8. **X1/X2/X3** — no build; revisit only if the backend adds Bearer multi-account,
   a tags endpoint, or a realtime channel.

---

## Part VI — Backend / API team asks (remaining)

Most prior asks are done (exports/GitHub/LinkedIn Bearer, moderation docs, push
field). What's left:

- **A1 — GitHub identity linking from mobile. ✅ DELIVERED (deployed + verified live
  2026-08-14).** `/auth/github/{authorize,callback}` now carry the mobile branch
  (mints a sync token → `interlinedlist://oauth/callback?token=…`); live probe:
  authorize accepts the mobile `redirect_uri` (307 → github.com) and rejects invalid
  ones. Residual is **iOS-only**: merge the staged `feat/github-oauth-universal-links`
  branch (**1 commit ahead of `dev`**, still unmerged as of 2026-08-15; flips GitHub
  `supportsNativeAuth → true`). *(The standalone `Backend-Asks-A1-A2.md` spec has been
  removed; the summary here is authoritative.)*
- **A2 — Universal Links assets. ✅ DELIVERED (deployed + Apple-CDN-verified
  2026-08-14).** `GET /.well-known/apple-app-site-association` serves the AASA JSON
  (200, `application/json`, no auth); Apple's CDN copy is cached (200). Residual is
  **iOS-only**: enable the Associated Domains capability in the Apple portal + regen
  the profile, then merge the staged entitlement (same `feat/github-oauth-universal-links`
  branch as A1).
- **A3 — Bearer for multi-account?** `/api/auth/{accounts,switch,remove-account}`
  are session-only. If mobile multi-account is desired, expose a Bearer-compatible
  switch (or per-account sync-tokens the client caches). Otherwise confirm it stays
  web-only and we'll drop it from scope (X1).
- **A4 — Doc residuals (low priority).** `POST /api/lists` response envelope
  (`{ message, data }`) still isn't documented; the doc-folder path-scoping caveat
  and the public-browse singular/plural namespace split are still worth a callout
  for future integrators.
- **A5 — List GET returns `folderId`. ✅ DELIVERED, then WITHDRAWN on the iOS side
  (2026-08-15).** The list **GET** does emit `folderId` (`getUserLists` uses Prisma
  `include`). However, iOS has **removed the list-folder concept entirely** by product
  decision: lists organize only via parent/child nesting (`parentId`), not folders. The
  client no longer decodes `folderId`, no longer calls the `/api/folders` CRUD
  endpoints, and no longer sends `folderId` on list create/update. **No backend change
  is requested** — the `folderId` column and `/api/folders/*` routes are simply unused
  by the iOS client now (backend cleanup optional; the web app never had folder UI).
- **A6 — Doc the new endpoints (low priority).** `/api/tags/{trending,autocomplete}`
  (G13) and `/api/link-metadata` (G14) shipped but aren't yet in `/help/api/*`; add
  pages so future integrators (and this doc) can rely on the published contract.

---

## Part VII — Coverage & method notes

- **Backend source read (2026-07-31):** enumerated `~/Codez/interlinedlist/app/api/**`
  route handlers; auth model derived per-route from the `getCurrentUserOrSyncToken`
  (Bearer|session) vs `getCurrentUser` (session-only) helper; subscriber gates from
  `isSubscriber` / `forbidden("Subscribe to …")`. Verb regressions (D1–D3) and the
  GitHub/exports/LinkedIn Bearer status were each confirmed by reading the exact
  route exports and auth helper — not by probing.
- **Docs read (2026-07-31):** all 21 `/help/api/*` pages, including the three new
  ones — **Direct Messages**, **Sharing**, **Moderation**.
- **iOS read (2026-07-31):** `APIClient.swift` (78 methods), 41 Views, 12 Models.
  **Re-read 2026-08-15:** `APIClient.swift` is now **148 methods**, ~52 Views, 19
  Models (reflecting G1–G14/G9 work landing on `dev`).
- **Live re-probe (2026-08-15):** fresh `POST /api/auth/sync-token` login + read-only
  GETs. **Confirmed:** `GET /api/lists` returns `folderId` (A5 done); `/api/tags/trending`
  and `/api/tags/autocomplete` return **200** with real data (G13 — supersedes X2);
  `/api/link-metadata` route reads Bearer (G14). Backend source re-scanned for new
  top-level `app/api/*` dirs since 2026-07-31 — new ones are `tags/` (G13),
  `link-metadata/` (G14), and `limits/` (a public, no-auth media/message-size caps
  endpoint — informational, not a parity gap; iOS could adopt it instead of hardcoding
  upload limits). No new mutations were performed.
- **Live probe (2026-07-31):** `messenger` (subscriber) via `POST
  /api/auth/sync-token` + read-only GETs (no mutations). Confirmed 200/Bearer on
  exports, DM (incl. `/thread/:username`, `/recipients`, `/unread-count`),
  templates, sync, tree, LinkedIn targets, people search, sessions, and share-link/
  collaborator reads; GitHub repos returned 400 "not linked" (auth passed). See
  [Live evidence](#live-verification-evidence-2026-07-31).
- **Still not observable (needs a write or a non-subscriber account):** the
  **free-user gating path** — what a non-subscriber sees for list/doc create and
  media/cross-post/schedule compose (source says 💲-gated; `messenger` is a
  subscriber so can't see the 403 path) — plus the `POST /api/documents/sync` write/
  conflict contract (G9) and the GitHub mobile-link OAuth flow (blocked, ask A1). No
  mutations were performed on the live account.

## Bottom line

The backend caught up: **exports, GitHub, and LinkedIn now accept Bearer**, and DMs
+ sharing + templates + sync shipped — all mobile-buildable. The only broken
shipped code is three one-line verb fixes (**D1–D3**). Everything else is additive
and self-contained. The highest-leverage new build is **Direct Messages (G1)**; the
highest-leverage unblock is **GitHub-backed lists (G4)**. The only true dead-ends
for mobile are **multi-account** (session-only) and a **general realtime channel**
(none exists — poll instead). *(Tag discovery is no longer a dead-end — see the
2026-08-15 update below.)*

> **Update 2026-08-14.** The plan above has been executed. **D1–D3 are fixed** and
> **G1–G10 + G12 all shipped** (see Progress log; G9 complete through Slice 3). What's
> left: **G11** presence (optional); **G10 follow-ons** (list/doc inbound + shared-token
> resolve); the **iOS-only** tail of A1/A2 (merge the staged
> `feat/github-oauth-universal-links` branch; enable the Apple-portal Associated
> Domains capability) now that **both A1/A2 backends are deployed and verified live**;
> and **A5** — the backend list **GET** must return `folderId` before the shipped
> "lists into folders" client UI can display nesting. *(A5 has since been delivered —
> see the 2026-08-15 update below.)*

> **Update 2026-08-15 (API re-verification).** Live Bearer re-probe + backend-source
> re-read. **A5 is now DELIVERED** — `GET /api/lists` returns `folderId` (verified),
> so **"lists into folders" works end-to-end** (only an iOS build/run confirmation
> remains). Two backend endpoints appeared since the last pass and have **no iOS
> consumer yet**: **G13** tag discovery (`/api/tags/{trending,autocomplete}`, which
> *supersedes X2* — tag trending is no longer a non-feature) and **G14** the composer
> live link-preview (`/api/link-metadata`). Net open work: **G13, G14, G11** (optional),
> **G10 follow-ons**, and the **iOS-only** A1/A2 merge (`feat/github-oauth-universal-links`,
> still 1 commit ahead of `dev`). No shipped code is broken; all remaining items are
> additive.
