# GAP-NEXT-STEPS — iOS implementation roadmap

What's left to build in this repo to bring the InterlinedList iOS app to
functionality parity with `interlinedlist.com` **and** clear the bar for a
first App Store submission.

This is the **iOS-side** punchlist. For backend endpoints that still need
to ship before some of these can be done, see `GAP-ENDPOINTS.md`. For the
signing / submission mechanics, see `GAP-APPLE.md`.

Last updated: 2026-06-27 — restructured around the remaining work after
Phases 2–8, 12 and feed-search shipped. Two things changed the shape of
this doc:

1. **Target = full web parity** before the first store submission, with
   **push (Phase 9) explicitly in v1**.
2. A new **ship-blocking** phase was added: **Phase 14 — UGC safety &
   moderation**. The app is a social/UGC app with **no content reporting,
   user blocking, muting, or terms-acceptance gate today** — Apple
   Guideline 1.2 requires all of these before a UGC app can pass review
   (see `GAP-APPLE.md` §5.4 / §11). This was previously only flagged in the
   Apple doc; it is now a tracked implementation phase.

The shipped-phase acceptance-criteria detail has been collapsed into the
table below (full history lives in git). Everything in the **Remaining
phases** section is genuinely unbuilt.

## Subscription / billing direction

The iOS app is a **free** app with **no subscription, billing, or
paywall UI**. Subscriber-only features are **hidden** for non-
subscribers; there is no "subscribe" call-to-action anywhere in the
bundle. Subscription management is entirely on the web at
`interlinedlist.com`. Full rationale and implementation details in
`subscription-permissions-update.md`.

---

## ✅ Shipped phases

| # | Phase | Shipped | Notes |
|---|---|---|---|
| 1 | Gap-closure + schema editor + subscriber awareness | 2026-06-23 | — |
| 2 | Auth surface parity | 2026-06-24 | reset, verify, OAuth ×5, identity linking, email change (entry + deep link + API + view). |
| 3 | Profile / account management | 2026-06-24 | Avatar upload + from-URL, organizations strip, delete-account. |
| B0 | Structured list-schema editing | 2026-06-25 | `updateListSchemaStructured` round-trips isVisible/isRequired/order; 409 → force-delete confirm. |
| 4 | Compose feature parity | 2026-06-25 | Cross-post toggles (Mastodon picker, Bluesky, LinkedIn, X) hidden for free users; repost; edit `scheduledAt`; crossPostResults toast; metadata endpoint wired. |
| 5 | Follow surface parity | 2026-06-25 | Followers/following (paginated), mutual-count strip, remove-follower, tappable counts. |
| 6 | List collaboration / watchers | 2026-06-25 | WatchersListView (roles, role picker, add/remove); Watch CTA on public lists. |
| 7 | Public browse end-to-end | 2026-06-25 | PublicListDetailView (read-only + Watch CTA), public Documents segment + reader. |
| 8 | Organizations | 2026-06-25 | Org list/detail/members CRUD, owner/admin/member roles, last-owner guard, create/edit/delete, join. *(Post-on-behalf-of-org NOT shipped → Phase 15.)* |
| 12 | Settings panel | 2026-06-25 | SettingsView (theme→PATCH, default visibility, advanced toggle, connected accounts, About webviews, sign-out) + NotificationPreferencesView. |
| 13a | Feed search | 2026-06-25 | `.searchable` feed → `GET /api/messages/search`. *(Tag discovery → Phase 13b, blocked §B6.)* |

---

## Status snapshot — what works today

- **Auth:** email/password + register; Keychain token; 401 → re-validate
  via `/api/user`. Password reset, email-verification banner, OAuth ×5
  (`ASWebAuthenticationSession`; LinkedIn/X hidden when unconfigured;
  GitHub hidden — no native callback), identity linking/disconnect,
  email-change deep links. Scheme `interlinedlist://`.
- **Feed:** infinite-scroll, pull-to-refresh, dig/undig, reply/delete,
  scheduled writes, search, link previews.
- **Compose:** text + image + video; cross-post toggles (subscriber-gated);
  repost; scheduled posts + edit.
- **Lists:** CRUD, folder CRUD (hidden for free users), structured schema
  editor, connections, items with typed fields, watchers/roles.
- **Documents:** CRUD, folder CRUD, search, public reader.
- **Public browse:** other users' public lists (detail + Watch CTA) and
  public documents.
- **Notifications:** tray, read/mark-all-read, follow-request approve/reject,
  per-event preferences catalog.
- **Profile:** view/edit, avatar upload + from-URL, organizations strip,
  delete-account (double-confirm → logout).
- **Follow:** follow/unfollow, status, counts, requests,
  followers/following/mutuals, remove-follower.
- **Organizations:** full CRUD + members + roles + join.
- **Settings:** theme, default visibility, advanced toggle, connected
  accounts, About webviews, sign-out.
- **Exports:** CSV for messages/lists/follows.

**Not yet present (the rest of this doc):** push notifications, inline
document image upload, offline document sync, **content reporting / user
blocking / muting / terms-acceptance gate**, posting on behalf of an org,
GitHub integration, tag discovery, realtime updates.

---

# Remaining phases

Phases are grouped by tier. Within a tier they're independent and each is a
self-contained PR (or a small series). The recommended landing order is
top-to-bottom.

## Tier 0 — Ship blockers (must land before the first App Store submission)

### Phase 14 — UGC safety & moderation   **Large**  ⛔ ship-blocker

The app is a social/UGC app but exposes **no way to report content, block
or mute a user, or accept terms**. Apple Guideline 1.2 requires UGC apps to
provide: (1) a method to report objectionable content, (2) a mechanism to
block abusive users, (3) an EULA/community agreement the user accepts that
states zero tolerance for objectionable content/abusive behaviour, and
(4) published developer contact info (the support URL covers this). Without
1–3 the app **will be rejected**.

There is currently no context menu or overflow action on feed rows
(`FeedView` has no `contextMenu`/`Menu`), so the entry points don't exist
yet anywhere.

> **Backend status: unverified.** It's not confirmed whether the backend
> exposes report/block/mute endpoints. **Start this phase with a short API
> discovery pass** (probe `/api/report`, `/api/users/:id/block`,
> `/api/blocks`, `/api/mute`, or whatever the web app calls). Record the
> real contracts in `GAP-ENDPOINTS.md` §H. If they don't exist, this phase
> is **blocked on backend** and that backend work becomes the true critical
> path to submission — escalate it immediately.

**Acceptance criteria:**

- [ ] **Discovery pass:** confirm the report/block/mute endpoint shapes;
      document them in `GAP-ENDPOINTS.md` §H (or file the backend gap).
- [ ] **Report content:** overflow (`Menu`) on every message row
      (`FeedView`, `MessageThreadView`, public list/profile message rows)
      with a "Report…" action → `ReportSheet` (reason picker + optional
      detail) → `POST` report endpoint. Confirmation toast.
- [ ] **Report user:** "Report @user" on `UserProfileView`.
- [ ] **Block user:** "Block @user" on the message overflow and
      `UserProfileView`. Blocking hides that user's content from the feed,
      replies, and public views (optimistic local filter + server call).
- [ ] **Mute user (optional if no backend):** local-only hide if there's no
      mute endpoint; server-backed if there is.
- [ ] **Blocked-users management:** new `BlockedUsersView` reachable from
      `SettingsView`; list blocked users, unblock.
- [ ] **Terms / community-guidelines acceptance:** add a required "I agree
      to the Terms & Community Guidelines" control to `RegisterView` that
      blocks submit until checked, linking to `/terms` and a
      community-guidelines/zero-tolerance page (confirm the URL exists —
      see `GAP-APPLE.md` open questions). Surface the same links in
      `SettingsView` ▸ About.
- [ ] Accessibility labels on all new controls; `#Preview` for new views.
- [ ] Unit tests for the new APIClient methods (MockURLSession) and a
      decoding test for the report/block models.

**Files:** new `Views/ReportSheet.swift`, `Views/BlockedUsersView.swift`,
new `Models/Moderation.swift`; edits to `Views/FeedView.swift`,
`Views/MessageThreadView.swift`, `Views/UserProfileView.swift`,
`Views/PublicListDetailView.swift`, `Views/RegisterView.swift`,
`Views/SettingsView.swift`, `Services/AppDataStore.swift` (local block
filter), `Services/APIClient.swift`.

**APIClient additions:** `reportMessage`, `reportUser`, `blockUser`,
`unblockUser`, `blockedUsers`, (`muteUser`/`unmuteUser` if supported).

**Dependencies:** backend report/block/mute endpoints (unverified — §H).

### Phase 0.5 — Pre-submission Info.plist / project hygiene   **Tiny**  ⛔ ship-blocker

Not a feature, but it gates the first upload and is a one-file PR. Fully
specified in `GAP-APPLE.md` §3.5 — pulled here so it isn't lost:

- [ ] Add `ITSAppUsesNonExemptEncryption=false` to `Info.plist`.
- [ ] Replace the stale `armv7` entry in `UIRequiredDeviceCapabilities`
      with `arm64`.
- [ ] Confirm `AppIcon` has no empty wells / no alpha.

**Files:** `InterlinedList/Info.plist`, `Assets.xcassets`.

---

## Tier 1 — v1 parity features

### Phase 9 — Push notifications (APNs)   **Medium**  ⭑ in v1

Backend ships `POST /api/push/register` / `DELETE /api/push/unregister`
with `platform: "ios"`. Confirmed in scope for the first release, so the
Xcode capability + entitlement land now (coordinate with `GAP-APPLE.md`
§2/§3.6 and the App ID push capability).

**Acceptance criteria:**

- [ ] Add the **Push Notifications** capability + `aps-environment`
      entitlement to the Xcode project; enable Push on the App ID in the
      developer portal (`GAP-APPLE.md` §2.3).
- [ ] Request notification permission on first launch **after login**
      (not at cold start).
- [ ] On `didRegisterForRemoteNotificationsWithDeviceToken`, POST the hex
      token to `/api/push/register`.
- [ ] On logout / token rotation, `DELETE /api/push/unregister`.
- [ ] Handle taps: route the payload's `actionUrl` through the existing
      `interlinedlist://` deep-link handler (Phase 2).
- [ ] Foreground-presentation + badge handling; clear badge on app open.
- [ ] Notification preferences already have a UI (Phase 12); confirm the
      catalog covers the push event types the server actually sends.

**Files:** new `Services/PushService.swift`, `InterlinedListApp.swift`
(lifecycle hooks via an `UIApplicationDelegateAdaptor`), Xcode project
(entitlements + capability).

**APIClient additions:** `registerPushDevice`, `unregisterPushDevice`.

**Dependencies:** Phase 2 (deep-link handler); signing/entitlement work in
`GAP-APPLE.md`.

### Phase 10 — Document inline image upload   **Small**

Self-contained; the public reader already shipped (Phase 7). Offline delta
sync is split out to Phase 16.

**Acceptance criteria:**

- [ ] In the document editor, pick/paste an image (`PhotosPicker`) →
      `POST /api/documents/:id/images/upload` → insert `![alt](url)` at the
      cursor.
- [ ] Upload progress + failure handling (reuse the message image-upload
      patterns from `uploadImage`).
- [ ] Accessibility label on the insert control; `#Preview` unaffected.
- [ ] APIClient unit test with MockURLSession (multipart shape).

**Files:** `Views/DocumentsView.swift` (image insertion handlers),
`Services/APIClient.swift`.

**APIClient additions:** `uploadDocumentImage(documentId:data:mimeType:)`.

**Dependencies:** none.

### Phase 15 — Post on behalf of an organization   **Small**

Phase 8 shipped org CRUD but **not** posting as an org. `postMessage` has
no `organizationId` field and `ComposeView` has no author picker. The web
app lets owners/admins post as an org.

**Acceptance criteria:**

- [ ] Confirm the create-message endpoint accepts an org-author field
      (name + camelCase casing — likely `organizationId` or
      `postAsOrganizationId`). If it doesn't, document as deferred in
      `GAP-ENDPOINTS.md` and stop.
- [ ] "Post as" picker in `ComposeView` (self vs. each org where the user
      is owner/admin), driven by `userOrganizations()` filtered by role.
- [ ] Thread the chosen org id through `postMessage(...)`.
- [ ] Show the org as author on the resulting feed row.

**Files:** `Views/ComposeView.swift`, `Services/APIClient.swift`
(extend `postMessage` + `CreateMessageBody`).

**Dependencies:** Phase 8 (orgs). Backend confirmation of the author field.

---

## Tier 2 — Larger / later parity

### Phase 16 — Document offline delta sync   **Large**

Split out of the old Phase 10. This is its own mini-project and should ship
behind a feature flag. Deferred relative to image upload.

**Acceptance criteria:**

- [ ] Delta sync via `/api/documents/sync` (GET + POST):
  - [ ] Background fetch every N minutes when authenticated.
  - [ ] Offline edits queued and POSTed as a batch on reconnect.
  - [ ] Conflict resolution: last-write-wins per doc (server side) with a
        banner if the local copy was overwritten.
- [ ] Significant rework to `AppDataStore` (treat sync as a distinct
      service); ship under a feature flag first.

**Files:** new `Services/DocumentSyncService.swift`, `AppDataStore.swift`,
`Views/DocumentsView.swift` (conflict banner).

**APIClient additions:** `syncDocuments(lastSyncAt:)`, `pushDocumentBatch`.

**Dependencies:** Phase 10 desirable first (shared editor surface), but
independent.

### Phase 17 — Realtime updates (WebSocket / SSE)   **Large**  (long-term)

Everything is pull-only today (`GAP-ENDPOINTS.md` §B8). With APNs (Phase 9)
covering the highest-value pushes, realtime is a polish item: live feed /
notification updates without a manual refresh. **Blocked** until the
backend exposes a realtime channel — keep documented, unscheduled.

**Dependencies:** backend realtime endpoint (§B8).

---

## Tier 3 — Blocked on backend (documented, not scheduled)

### Phase 11 — GitHub integration   **Medium**  — deferred (§B4)

`/api/github/*` requires **session-cookie** auth and rejects Bearer tokens;
iOS is Bearer-only. Recommendation unchanged: **ask the backend** for
Bearer support (or a `session-from-bearer` exchange) before building
anything. Do not add a cookie jar to APIClient just for GitHub — it
bypasses the Bearer security model. Deferred until the backend decision
lands.

**Files (if pursued):** `Services/GitHubService.swift`,
`Views/GitHubBackedListView.swift`, `Views/CreateIssueFromMessageView.swift`.

### Phase 13b — Tag discovery   **Small**  — blocked (§B6)

Feed search shipped (13a). Tag discovery needs endpoints that don't exist:
`GET /api/tags/trending` and `GET /api/tags/autocomplete`. `?tag=`
filtering already works, but there's no discovery/autocomplete path.

When the endpoints ship:

- [ ] Tag explorer (trending) → tap a tag → filtered feed.
- [ ] `#…` autocomplete inside `ComposeView`.

### Phase 18 — LinkedIn org cross-post targets   **Small**  — blocked (§D2)

Cross-posting ships the simple `crossPostToLinkedIn` boolean. Targeting a
specific LinkedIn **organization** page needs the `linkedInTargets[].kind`
vocabulary (`personal`/`organization`?) and whether an org target carries
an `organizationId` — both undocumented (§D2). Low iOS relevance; ship only
after the contract is published.

---

## Effort summary

| # | Phase | Tier | Effort | Status |
|---|---|---|---|---|
| 14 | UGC safety & moderation (report/block/mute + terms gate) | 0 | Large | ⛔ ship-blocker — **start here**; backend unverified (§H) |
| 0.5 | Info.plist / project hygiene | 0 | Tiny | ⛔ ship-blocker (one-file PR; `GAP-APPLE.md` §3.5) |
| 9 | Push notifications (APNs) | 1 | Medium | ⭑ in v1 — needs Xcode capability + entitlement + App ID push |
| 10 | Document inline image upload | 1 | Small | not started |
| 15 | Post on behalf of an organization | 1 | Small | not started; backend author-field unconfirmed |
| 16 | Document offline delta sync | 2 | Large | not started (feature-flagged) |
| 17 | Realtime updates (WebSocket/SSE) | 2 | Large | blocked (§B8) |
| 11 | GitHub integration | 3 | Medium | deferred (§B4) |
| 13b | Tag discovery | 3 | Small | blocked (§B6) |
| 18 | LinkedIn org cross-post targets | 3 | Small | blocked (§D2) |

**Critical path to the App Store:** Phase 14 + Phase 0.5 (Tier 0) must land
first, then the v1 parity features (9, 10, 15). Tier 2/3 can follow the
first submission. The single biggest risk is Phase 14's backend dependency —
resolve the discovery pass early.

---

## How to use this doc

- Pick a phase; check the acceptance criteria; ship them in order
  (Tier 0 → 1 → 2 → 3).
- Mark items `[x]` as they land.
- Each phase is an independent PR (or a small series) — feature-flag where
  noted.
- When a phase completes, move its summary line into the **Shipped phases**
  table and delete its per-phase detail to keep the doc scannable.
- For any new endpoint discovered mid-phase that doesn't yet exist on the
  backend, add it to `GAP-ENDPOINTS.md` instead of inlining it here.
