# GAP-NEXT-STEPS — iOS implementation roadmap

What's left to build in this repo to bring the InterlinedList iOS app to
functionality parity with `interlinedlist.com`.

This is the **iOS-side** punchlist. For backend endpoints that still need
to ship before some of these can be done, see `GAP-ENDPOINTS.md`.

Last updated: 2026-06-24 — after Phase 2 (auth surface) and Phase 3
(profile / account management) shipped.

## Subscription / billing direction

The iOS app is a **free** app with **no subscription, billing, or
paywall UI**. Subscriber-only features are **hidden** for non-
subscribers; there is no "subscribe" call-to-action anywhere in the
bundle. Subscription management is entirely on the web at
`interlinedlist.com`. Full rationale and implementation details in
`subscription-permissions-update.md`.

## ✅ Shipped phases

| # | Phase | Shipped | Notes |
|---|---|---|---|
| 1 | Gap-closure + schema editor + subscriber awareness | 2026-06-23 | — |
| 2 | Auth surface parity | 2026-06-24 | Fully closed: reset, verify, OAuth ×5, identity linking, and email change (entry row + deep link + API + view) all in. |
| 3 | Profile / account management | 2026-06-24 | Avatar upload + from-URL, organizations strip, delete-account all in. |

Per-phase detail for 1–3 has been collapsed to short stubs below; the
full acceptance-criteria history lives in git. Remaining work starts at
Phase 4.

## Status snapshot — what works today

The current app supports:

- **Auth:** email/password login + register via `/api/auth/sync-token`,
  Keychain token storage, 401 → auto-logout. Plus (Phase 2) password
  reset, email-verification banner, OAuth sign-in for GitHub / Mastodon /
  Bluesky / LinkedIn / X via `ASWebAuthenticationSession` (LinkedIn/X
  hidden when their `/status` says unconfigured), identity linking /
  disconnect, and email-change deep links. Custom URL scheme
  `interlinedlist://` handles reset-password / verify-email /
  verify-email-change / oauth callbacks.
- **Feed:** infinite-scroll messages, pull-to-refresh, dig/undig,
  reply/delete, scheduled-at writes are wired in `postMessage`.
- **Compose:** text + image (1) + video (1) attachments; advanced toolbar
  has placeholder `M`/`BS`/`in` icons (Mastodon/Bluesky/LinkedIn) that
  are disabled stubs.
- **Lists:** CRUD, folder CRUD (folder UI hidden entirely for free users — see `subscription-permissions-update.md`),
  schema editor with non-destructive DSL save, list connections, list
  items add/edit/delete with typed fields.
- **Documents:** CRUD, folder CRUD, search.
- **Notifications:** tray fetch, read/mark-all-read, follow-request
  approve/reject inline.
- **Profile:** view + edit (display name, bio, default visibility),
  public profile view of other users with public lists & messages. Plus
  (Phase 3) avatar upload from photo library + set-from-URL,
  organizations strip on profile, and delete-account with
  double-confirmation → forced logout.
- **Follow:** follow/unfollow, status, counts, requests.
- **Exports:** CSV for messages/lists/follows.
- **`customerStatus`** is now decoded on `User` with an `isSubscriber`
  computed predicate.

What's still missing — broken out into phases below.

---

## Phase 2 — Auth surface parity   ✅ Shipped 2026-06-24

Password reset, email-verification banner + post gating, OAuth ×5
(`ASWebAuthenticationSession`, LinkedIn/X hidden when unconfigured,
Mastodon instance prompt), identity linking/disconnect, and the
`interlinedlist://` deep-link handler (reset-password / verify-email /
verify-email-change / oauth callback) all landed.

**Shipped files:** `LoginView`, `RegisterView`, `ForgotPasswordView`,
`ResetPasswordView`, `LinkedIdentitiesView`, `EmailVerificationBanner`,
`OAuthSignInButton`, `Services/OAuthCoordinator`, `ChangeEmailView`,
`AuthState`, `InterlinedListApp` (URL scheme), `Info.plist`
(`CFBundleURLSchemes`). **APIClient:** `forgotPassword`, `resetPassword`,
`sendVerificationEmail`, `verifyEmail`, `verifyEmailChange`,
`linkedIdentities`, `unlinkIdentity`, `requestEmailChange`,
`linkedinStatus`, `twitterStatus`.

Email change is fully wired: `EditProfileView`'s Account section has a
tappable "Change" row that presents `ChangeEmailView` as a sheet, which
posts to `/api/user/change-email/request`; the `verify-email-change`
deep link then completes the change. No remaining items.

---

## Phase 3 — Profile / account management   ✅ Shipped 2026-06-24

Avatar upload from photo library (`PhotosPicker` → `uploadAvatar`) and
set-from-URL (`setAvatarFromURL`), the organizations strip on
`UserProfileView` (`userOrganizations`), and delete-account with
double-confirmation → forced logout (`deleteAccount`) all landed in
`EditProfileView` / `UserProfileView`. The "Subscriber CTA on profile"
item was dropped 2026-06-24 (no subscription UI on iOS — see
`subscription-permissions-update.md`).

---

## Phase 4 — Compose feature parity   **Medium**

`ComposeView` has the scaffolding for cross-posting (the `M`/`BS`/`in`
buttons exist as `.disabled(true)` placeholders); `scheduledAt` is
already plumbed through `postMessage`.

**Acceptance criteria:**

- [ ] Replace the three placeholder cross-post buttons (`ComposeView.swift:170–193`)
      with real toggles bound to state vars `crossPostToMastodon`
      (per-instance), `crossPostToBluesky`, `crossPostToLinkedIn`,
      `crossPostToTwitter`.
- [ ] Add an X/Twitter icon — currently only three placeholders.
- [ ] Mastodon picker driven by `GET /api/user/identities` filtered to
      `provider == "mastodon"`; sends `mastodonProviderIds[]`.
- [ ] Pass `crossPostToBluesky`, `crossPostToLinkedIn`,
      `crossPostToTwitter` to `APIClient.postMessage(...)`.
- [ ] **Hide** every cross-post control when
      `authState.user?.isSubscriber != true`. No disable-with-paywall;
      free users never see the controls. See
      `subscription-permissions-update.md`.
- [ ] Surface `crossPostResults` from the response in a toast after
      posting ("Posted to Bluesky ✓ · Mastodon ✗ rate-limited").
- [ ] Confirm the scheduling UI (calendar icon + date picker) is
      end-to-end — including the "future date required" validation.
      Add tests around the ISO formatter.
- [ ] Edit scheduled posts: open `EditMessageView` for a scheduled
      message, allow changing `scheduledAt` via
      `PATCH /api/messages/:id`.
- [ ] Repost flow: "Repost" action on feed items → posts a new message
      with `pushedMessageId` set, no `content`.
- [ ] **New endpoint surfaced 2026-06-23:**
      `POST /api/messages/:id/metadata` — purpose not yet investigated
      (link preview / OG-tag attach?). Worth a short discovery pass
      during Phase 4 to decide whether to expose it.

**Files:** `Views/ComposeView.swift`, `Views/EditMessageView.swift`,
`Views/FeedView.swift` (repost action), `Services/APIClient.swift`
(extend `postMessage` signature).

**APIClient additions:** extend `postMessage` with cross-post params;
add `patchMessage(id:, scheduledAt:, scheduledCrossPostConfig:)`; possibly
`setMessageMetadata(...)`.

**Dependencies:** `customerStatus` (already shipped). Phase 2 identities
endpoint for the Mastodon picker.

---

## Phase 5 — Follow surface parity   **Small**

**Acceptance criteria:**

- [ ] `FollowersListView` — `GET /api/follow/:userId/followers`,
      paginated, push to `UserProfileView`.
- [ ] `FollowingListView` — symmetric.
- [ ] "Mutual" strip on `UserProfileView` — `GET /api/follow/:userId/mutual`.
- [ ] "Remove follower" action on FollowersListView (only for own
      profile) — `DELETE /api/follow/:userId/remove`.
- [ ] Tap counts on `UserProfileView` to navigate to the lists.

**Files:** new `Views/FollowersListView.swift`,
`Views/FollowingListView.swift`, `Views/UserProfileView.swift`.

**APIClient additions:** `followers`, `following`, `mutualFollows`,
`removeFollower`.

**Dependencies:** none.

---

## Phase 6 — List collaboration / watchers   **Large**

Site supports three roles per public list: Watcher, Collaborator,
Manager. iOS has nothing.

**Acceptance criteria:**

- [ ] `WatchersListView` on a list — `GET /api/lists/:id/watchers/users`
      with each user's role.
- [ ] "My role" badge — `GET /api/lists/:id/watchers/me`.
- [ ] "Watch" CTA on public list detail — `POST /api/lists/:id/watchers`.
- [ ] Manager-only: change role via picker
      (`PUT /api/lists/:id/watchers/:userId`).
- [ ] Manager-only: remove member
      (`DELETE /api/lists/:id/watchers/:userId`).
- [ ] **Permission model**: `ListDetailView` hides schema editor for
      non-Managers, hides row add/edit/delete for non-Collaborators,
      shows read-only view for Watchers. Plumb the current user's role
      from `/watchers/me` down to all child views.
- [ ] Confirm role values match docs once they're published (the docs
      list endpoints but don't enumerate role strings — see
      `GAP-ENDPOINTS.md` §B5).

**Files:** new `Views/WatchersListView.swift`, `Views/ListsView.swift`
(permission gating), new `Models/ListWatcher.swift`.

**APIClient additions:** `listWatchers`, `listWatchersUsers`,
`myListRole`, `addWatcher`, `setWatcherRole`, `removeWatcher`.

**Dependencies:** Phase 7 (need public-list browse to give Watchers a
target to watch).

---

## Phase 7 — Public browse end-to-end   **Small**

`UserProfileView` already lists a user's public lists. There's no detail
flow yet.

**Acceptance criteria:**

- [ ] Tap a public list on a profile → `PublicListDetailView`
      (`GET /api/users/:username/lists/:id` + `/data`).
- [ ] Same view as the owner's `ListDetailView` but read-only, with a
      "Watch" CTA (depends on Phase 6 endpoint).
- [ ] `PublicDocumentsView` on a profile —
      `GET /api/users/:username/documents`.
- [ ] Tap a public document → read-only renderer.

**Files:** new `Views/PublicListDetailView.swift`,
`Views/PublicDocumentsView.swift`, new `Views/PublicDocumentReader.swift`.

**APIClient additions:** `publicListDetail`, `publicListData`,
`publicDocuments`, `publicDocument`.

**Dependencies:** none for browsing; the "Watch" CTA needs Phase 6.

---

## Phase 8 — Organizations   **Large**

Site has full org CRUD with `owner`/`admin`/`member` roles. iOS has
nothing.

**Acceptance criteria:**

- [ ] "Organizations" entry in profile → `OrganizationsListView`.
- [ ] Create / rename / delete orgs (owner-only).
- [ ] Members list + role picker
      (`/api/organizations/:id/members*`).
- [ ] Enforce "last owner cannot be demoted/removed" client-side with a
      disabled control + tooltip.
- [ ] Post-on-behalf-of-org from `ComposeView` (optional v1.5 — only
      ship if the message endpoint accepts an `organizationId`-style
      field; otherwise document as deferred).
- [ ] LinkedIn-per-org integration is **deferred** — complex, low iOS
      relevance for a v1.

**Files:** new `Views/OrganizationsListView.swift`,
`Views/OrganizationDetailView.swift`, `Views/OrganizationMembersView.swift`,
new `Models/Organization.swift`.

**APIClient additions:** full org CRUD + members CRUD.

**Dependencies:** none.

---

## Phase 9 — Push notifications (APNs)   **Medium**

Backend ships `POST /api/push/register` and `DELETE /api/push/unregister`
with `platform: "ios"`. No iOS push support today.

**Acceptance criteria:**

- [ ] Add Push Notifications capability + APNs entitlement to the Xcode
      project.
- [ ] Request user permission on first launch after login.
- [ ] On `didRegisterForRemoteNotificationsWithDeviceToken`, ship the
      token to `POST /api/push/register` (hex format).
- [ ] On logout / token rotation, call `DELETE /api/push/unregister`.
- [ ] Handle incoming notification payloads: tap → deep link via the
      notification's `actionUrl` (use the same URL handler from
      Phase 2).
- [ ] **Notification preferences screen** — blocked on backend: there's
      no endpoint that enumerates which event types exist. See
      `GAP-ENDPOINTS.md` §B3. Until that ships, iOS receives whatever
      the server decides to send based on user-profile settings updated
      via the web.

**Files:** new `Services/PushService.swift`,
`InterlinedListApp.swift` (lifecycle hooks), Xcode project
(entitlements + capability).

**APIClient additions:** `registerPushDevice`, `unregisterPushDevice`.

**Dependencies:** Phase 2 (deep-link handler for `actionUrl`).

---

## Phase 10 — Documents enhancements   **Large**

**Acceptance criteria:**

- [ ] Inline image upload in document editor: paste/drag image →
      `POST /api/documents/:id/images/upload` → insert `![alt](url)`
      at cursor.
- [ ] Delta sync via `/api/documents/sync` (GET + POST):
  - [ ] Background fetch every N minutes when authenticated.
  - [ ] Offline edits queued and POSTed as batch on reconnect.
  - [ ] Conflict resolution: last-write-wins per doc (server side)
        with a banner if the user's local copy was overwritten.
  - [ ] Significant rework to `AppDataStore` — treat as its own
        mini-project; ship under a feature flag first.
- [ ] Public document reader for `/api/documents/:id` when the
      document is `isPublic`.

**Files:** new `Services/DocumentSyncService.swift`,
`Views/DocumentsView.swift` (image insertion handlers),
new `Views/PublicDocumentReader.swift` (also referenced by Phase 7).

**APIClient additions:** `uploadDocumentImage`, `syncDocuments(lastSyncAt:)`,
`pushDocumentBatch(...)`.

**Dependencies:** none for image upload; sync is independent of other
phases but heavy.

---

## Phase 11 — GitHub integration   **Medium**

Backend exposes `/api/github/repos`, `/api/github/issues`, etc. — but
they require **session cookie** auth (Bearer tokens not accepted). iOS
uses Bearer tokens.

**Acceptance criteria:**

- [ ] Detect whether the current user has an active GitHub identity
      (Phase 2 endpoint).
- [ ] If GitHub features are needed in iOS, two options — pick one:
  - [ ] (a) Add session-cookie support to APIClient (cookie jar +
            cookie-based auth flow), used only for `/api/github/*`. Or
  - [ ] (b) Defer to backend: ask for Bearer-token support on the
            GitHub endpoints. See `GAP-ENDPOINTS.md` §B4.
- [ ] If (a): GitHub-backed list creation, "create issue from message",
      assignee/label pickers, "next issue number" helper.

**Recommendation:** ask the backend first. Cookie support on iOS is
fragile and bypasses our Bearer-token security model. Mark this phase
**deferred** until the backend decision lands.

**Files (if pursued):** new `Services/GitHubService.swift`,
`Views/GitHubBackedListView.swift`, `Views/CreateIssueFromMessageView.swift`.

---

## Phase 12 — Settings panel + webview content   **Small**

There is currently **no Settings view** in the app. Account-level
settings sit inside `EditProfileView`; preferences like theme and
default visibility are partial.

**Acceptance criteria:**

- [ ] New `Views/SettingsView.swift`, presented from a gear icon on
      `MainTabView` or as a section in the profile tab. Surface:
  - [ ] Theme (`light` / `dark` / `system`) — bound to
        `PATCH /api/user/update` `theme` field.
  - [ ] Default visibility — already on `EditProfileView`; move here.
  - [ ] Max message length — read-only display from `user.maxMessageLength`.
  - [ ] Show advanced post settings — boolean.
  - [ ] Connected accounts → Phase 2 `LinkedIdentitiesView`.
<!-- "Subscription status + manage subscription" REMOVED 2026-06-24. The
       iOS app shows no subscription UI; subscription management is
       entirely on the web. -->
  - [ ] Notification preferences → Phase 9 (currently blocked).
  - [ ] About → `SFSafariViewController` for `/blog`, `/pricing`,
        `/terms`, `/privacy`, `/help/branding`.
  - [ ] Sign out (move from `UserProfileView`).
- [ ] `SettingsView` is the natural home for many things that have been
      bolted onto `EditProfileView`. Refactor accordingly.

**Files:** new `Views/SettingsView.swift`, `Views/MainTabView.swift`
(entry point), `Views/EditProfileView.swift` (slim down),
`Views/UserProfileView.swift` (remove Sign-Out — now in Settings).

**Dependencies:** none for the static portions; Phase 2/3/9 each light
up additional rows as they ship.

---

## Phase 13 — Feed search + tag discovery   **Small** (blocked)

The website filters the feed by hashtag (`?tag=X`) and presumably
surfaces tag suggestions. iOS has no search box on the feed and no tag
explorer.

**Blocked on backend gaps** — see `GAP-ENDPOINTS.md` §B2 (message
search) and §B6 (tag discovery). Without those endpoints, iOS can only
support tag filtering via direct entry, which has no discovery path.

When the endpoints ship:

- [ ] Search bar on `FeedView` — `GET /api/messages/search?q=...`.
- [ ] Tag explorer — `GET /api/tags/trending` or similar; tap a tag →
      filtered feed.
- [ ] Tag autocomplete inside `ComposeView` `#…` entry.

---

## Effort summary

| # | Phase | Effort | Status |
|---|---|---|---|
| 2 | Auth (reset / verify / OAuth ×5 / linking / email change) | Medium | ✅ shipped 2026-06-24 |
| 3 | Profile / avatar / orgs / delete account | Small | ✅ shipped 2026-06-24 |
| 4 | Compose: schedule + cross-post + gating + edit / repost | Medium | scaffold present, needs wiring |
| 5 | Followers / following / mutuals / remove-follower | Small | not started |
| 6 | List watchers / roles / permission model | Large | not started |
| 7 | Public browse end-to-end | Small | not started |
| 8 | Organizations | Large | not started |
| 9 | Push notifications (APNs) | Medium | not started |
| 10 | Documents: image upload + sync + public reader | Large | not started |
| 11 | GitHub integration | Medium | **deferred** (auth model conflict) |
| 12 | Settings panel + webview content | Small | not started |
| 13 | Feed search + tag discovery | Small | **blocked on backend** |

With Phases 1–3 shipped, the remaining unblocked work is Phases 4–10 and
12. Phase 13 lights up automatically once the backend endpoints ship.

---

## How to use this doc

- Pick a phase; check the acceptance criteria; ship them in order.
- Mark items `[x]` as they land.
- Each phase is independently shippable behind a feature flag if needed.
- When a phase completes, move its summary line to a "✅ Done" section
  at the top of this file (delete the per-phase detail to keep the doc
  scannable).
- For any new endpoint discovered mid-phase that doesn't yet exist on
  the backend, add it to `GAP-ENDPOINTS.md` instead of inlining it
  here.
