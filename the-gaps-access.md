# the-gaps-access.md — Access-Control Gap Analysis

**Scope:** Does a user only get the things they have access to based on **subscription**, **role**, or **approved/cleared status**? This reviews the iOS client (`InterlinedList/`) and cross-references the backend at `~/Codez/interlinedlist/` for the source-of-truth enforcement.

**Audited:** 2026-08-15 · **Reviewer:** automated audit (Claude) · **Remediation verified:** 2026-09-05

> **✅ ALL SEVEN GAPS ARE CLOSED.** G1–G7 were fixed on 2026-08-15 and merged
> 2026-08-16 as one PR each (**#17–#23**). Re-verified against the working tree on
> 2026-09-05 — every remediation below is present in shipped code (per-gap evidence
> in each section and in the [§5 table](#5-prioritized-remediation)). This document is
> retained as the **audit record and the pattern reference** for future access-control
> work, not as an open backlog.

---

## 1. Executive summary

**The backend enforces every access rule server-side** (verified — see §2). Non-subscribers, non-owners, wrong-role users, and unverified-email users all receive `403 Forbidden` from the API regardless of what the app does. **There is no unauthorized-data-exposure vulnerability here.** Defense-in-depth is intact.

The gaps are therefore **client-side correctness / consistency / UX**, plus **one App Store-review risk**:

*(All three findings below describe the **2026-08-15 audit state**; each was fixed the same day — see the status column and the per-gap "Shipped" notes.)*

- The client uses three separate access axes — **subscription** (`isSubscriber`), **role** (`OrgRole`, `WatcherRole`), and **cleared status** (`emailVerified`) — but applied them **inconsistently**. One premium surface (list-watcher management) wasn't gated at all, while its exact twin (document collaborators) was. *(Fixed — G1.)*
- Entitlement state (`customerStatus`) was **cached and rarely refreshed**, so it went stale when the subscription changed on the web (where billing lives). *(Fixed — G2.)*
- Authorization `403`s surfaced the **raw backend message**, and the app's intended friendly/typed 403 handling was **dead code** — a correctness bug and a potential IAP-steering issue if that text contains upsell copy. *(Fixed — G3.)*

None of these leaked data. All of them could make a paying/entitled user see the wrong thing, or make a non-entitled user tap controls that always fail.

### Severity legend
Severity reflects **product/UX correctness and store-review risk**, not data security (all paths are server-enforced).

| ID | Gap | Severity | Status |
|----|-----|----------|--------|
| G1 | List-watcher management not subscriber-gated (inconsistent with documents) | **Medium** | ✅ Fixed `65169a9` (PR #17) |
| G2 | Stale subscription/entitlement state — no refresh on foreground | **Medium** | ✅ Fixed `0fa483a` (PR #18) |
| G3 | Authorization 403s surface raw backend text; friendly/typed handling is dead code | **Medium** (store-review) | ✅ Fixed `eb6b964` (PR #19) |
| G4 | Client can't distinguish owned vs shared lists (`UserList` has no owner/role field) | **Low** (latent) | ✅ Fixed `179889a` (PR #20) |
| G5 | Free owners over-restricted from removing document collaborators | **Low** | ✅ Fixed `a284d60` (PR #21) |
| G6 | Email-verification gating coverage is uneven (media upload not pre-gated) | **Low** | ✅ Fixed `f772fd1` (PR #22) |
| G7 | `WatchersListView` 401 handling deviates from the app's 401 contract | **Low** | ✅ Fixed `d4c5fd6` (PR #23) |

---

## 2. The access-control model (as built)

### Three axes + one clearance flag

| Axis | Source of truth (client) | Where derived | Backend enforcement |
|------|--------------------------|---------------|---------------------|
| **Subscription** | `User.customerStatus` → `User.isSubscriber` (prefix `"subscriber"`) — `Models/User.swift:37` | `GET /api/user` | `isSubscriber(customerStatus)` guard → `403` on sharing, folders, media, cross-post, scheduling, GitHub-backed lists |
| **Org role** | `Organization.userRole` → `OrgRole` (member<admin<owner) — `Models/Organization.swift:9-31` | `GET /api/organizations/...` | `hasPermission(role, required)` hierarchy → `403` |
| **Sharing role** | `WatcherRole` (watcher<collaborator<manager) — `Models/ListWatcher.swift:10-49` | watcher/collaborator endpoints | `getListAccess()` tiers → `403`; watcher-list endpoints are owner-only |
| **Cleared status** | `User.emailVerified` | `GET /api/user` | `!user.emailVerified` → `403` on posting + media upload; follow-request approval; email-invite claim requires matching verified email |

### Backend enforcement — confirmed (source of truth)

Verified in the backend repo. Representative guards:

- `lib/subscription/is-subscriber.ts` — `customerStatus === 'subscriber' || startsWith('subscriber:')`.
- Subscriber-gated `→403`: `POST /api/lists` (create), `POST /api/{lists,documents}/[id]/share-links`, `POST /api/lists/[id]/watchers` (named user), `POST /api/documents/[id]/collaborators`, `PUT .../watchers/[userId]`, `PUT .../collaborators/[userId]`, `POST /api/folders`, `POST /api/documents/folders`, `POST /api/messages/{images,videos}/upload`, and `POST /api/messages` when it carries cross-post/images/video/schedule.
- Role-tiered `→403`: read = watcher, row writes = collaborator, schema/metadata edits = manager; watcher/collaborator **list & role-change** endpoints are **owner-only**.
- Email-verified `→403`: `POST /api/messages`, media upload, list-invite claim.
- Follow/private: pending→accepted request model; blocking prevents follow/push/reply; private orgs require admin invite.

**Conclusion:** The server correctly rejects any request that the client's UI gating would have prevented. Everything below is about the **client** presenting the wrong affordances.

---

## 3. Gaps

### G1 — List-watcher management is not subscriber-gated (Medium) — ✅ FIXED

**The app gates the identical feature two different ways.** Document collaborators, share-links, and share-invites all hide their *create* controls for non-subscribers:

- `Views/DocumentCollaboratorsView.swift:23` — `canManage = authState.user?.isSubscriber == true` (hides Add + role menu + remove).
- `Views/ShareLinksSheet.swift:29` — `canCreate = isSubscriber` (hides "Create link").
- `Views/ShareInvitesSheet.swift:33` — `canInvite = isSubscriber` (hides "Send invite").

But **`Views/WatchersListView.swift` has no subscriber gate at all.** The "Add watcher" toolbar button (`:45-48`) is always shown, and the role-change `Menu` (`:142-161`) is always active. The backend requires a subscription for `POST /api/lists/[id]/watchers` (named user) and `PUT /api/lists/[id]/watchers/[userId]`.

**Impact:** A non-subscribing **owner** of a list (the Lists tab shows only owned lists — see §4) sees a fully functional-looking watcher manager. Every "add" (`WatchersListView.swift:280-291`) and every role change (`:101-112`) returns `403`, and the error path surfaces the **raw backend message** (`self.error = msg`). Confusing, and off-brand versus the rest of the app which hides-not-paywalls.

**Fix:** Mirror `DocumentCollaboratorsView`: introduce `canManage = authState.user?.isSubscriber == true`, gate the toolbar "Add watcher" button and the role-change menu on it. Viewing/removing existing watchers can stay available to any owner (the GET and DELETE are not subscriber-gated server-side).

**Shipped (`65169a9`, PR #17):** `WatchersListView.swift:26` now defines `canManage = authState.user?.isSubscriber == true`; the toolbar "Add watcher" button (`:51`) and the row role-change menu (`:82`, `:142`, `:156`) are gated on it. Viewing and removing existing watchers stay available to any owner, matching the server.

---

### G2 — Stale subscription/entitlement state; no foreground refresh (Medium) — ✅ FIXED

`isSubscriber` is derived from `User.customerStatus`, which is cached in `AuthState.user` and only re-fetched on:
- launch/login/OAuth (`Services/AuthState.swift:33,52,76`),
- `handleUnauthorized()` re-validation (`:126`),
- `refreshUser()` — which is **only called from the email-verify deep-link handlers** (`InterlinedListApp.swift:93,105`).

There is **no `scenePhase == .active` refresh** and no refresh before presenting premium UI. Per `CLAUDE.md`, subscriptions/sharing are managed on the **web** (iOS ships as a free app with no IAP).

**Impact:**
- **Cancel/refund/expiry on web** → the app keeps `isSubscriber == true`, keeps showing premium controls, and every premium action `403`s (into the raw-text path of G3) until the next relaunch/login.
- **Subscribe on web while the app is backgrounded** → the app keeps `isSubscriber == false` and keeps premium features hidden — the user paid but can't see what they bought until relaunch.

**Fix:** Refresh the user on foreground (`.onChange(of: scenePhase)` → `.active` → `authState.refreshUser()`), and immediately after returning from any web billing/settings link. Cheap `GET /api/user`; keeps entitlement fresh.

**Shipped (`0fa483a`, PR #18):** `InterlinedListApp.swift:39-46` refreshes on foreground — `.onChange(of: scenePhase)` → `if phase == .active, authState.hasToken { await authState.refreshUser() }` — so entitlement and `emailVerified` re-sync after any web-side subscription change.

---

### G3 — Authorization 403s surface raw backend text; typed handling is dead code (Medium, store-review) — ✅ FIXED

`checkResponse` maps **any 4xx that has a JSON `{"error": …}` body** to `APIError.server(msg)` — *not* to `APIError.status(403)`:

```swift
// Services/APIClient.swift:1748-1758
if http.statusCode == 401 { throw APIError.status(401) }
if http.statusCode >= 400 {
    if let err = try? decoder.decode(ErrorResponse.self, from: data) { throw APIError.server(err.error) }
    throw APIError.status(http.statusCode)
}
```

The backend's `forbidden(msg)` returns `{"error": msg}`, so **403s arrive as `.server(msg)`**. Every `catch APIError.status(403)` in the app is therefore effectively **unreachable**, and the raw backend string is shown instead:

- `Views/ComposeView.swift:719-722` — `.server(message)` catch fires first (shows raw text); the friendly `catch APIError.status(403) { "You may need to verify your email…" }` never runs.
- `Views/ShareInvitesSheet.swift:167-171` — the `catch APIError.status(403)` neutral-message branch is dead; a body-bearing 403 falls to the generic catch → "Could not send this invite." (harmless here, but the intent is broken).
- `Views/WatchersListView.swift`, `Views/DocumentCollaboratorsView.swift`, `Views/CreateListView.swift` — the `.server(msg)` path shows the backend string verbatim.

**Impact:**
1. **Correctness:** intended friendly copy never appears; users see server phrasing.
2. **App Store Review risk (Guideline 3.1.1):** if any subscriber-gate 403 message contains upsell/"Subscribe" copy, that external-purchase steering is rendered inside the app. The team already worried about this (see the deliberate comments at `ComposeView.swift:60-63` and `uploadVideo` at `:663-666`), but the raw-text path defeats it wherever a stale-entitlement 403 slips through (G2).

**Fix:** Add a typed forbidden case (e.g. map `403` to `APIError.forbidden(msg)` in `checkResponse`, distinct from generic `.server`). Then views can convert authorization failures to **neutral in-app copy** and never surface raw upsell text. At minimum, stop relying on the currently-dead `.status(403)` branches.

**Shipped (`eb6b964`, PR #19):** `APIError.forbidden(String)` exists (`APIClient.swift:23`) and `checkResponse` maps body-bearing 403s to it (`:1796`); bodyless 403s stay `.status(403)`. Views catch the typed case and substitute neutral copy — `ComposeView.swift:728`, `ShareInvitesSheet.swift:167`, `NotificationsView.swift:105`, `DMThreadView.swift:252` — so raw backend text (and any upsell phrasing in it) is never rendered in-app.

---

### G4 — Client can't distinguish owned vs shared lists (Low, latent) — ✅ FIXED

`UserList` (`Models/List.swift:122-171`) carries **no `userId` / owner / role field**. `ListDetailView`'s toolbar shows **Manage watchers / Share / Invite** unconditionally (`Views/ListsView.swift:492-515`) with no ownership gate — it *can't* gate, because the model has no ownership signal.

**Currently masked:** `GET /api/lists` returns **owner-only** lists (verified: `getUserLists` filters by `userId` with no watcher/`OR` clause), so the Lists tab never contains shared-in lists and the toolbar is only ever seen by owners. **No live defect today.**

**Why it's still a gap:** it's a latent inconsistency. If the list index is ever broadened to include shared/watched lists (the self-watch-public-lists feature makes this plausible), non-owners would suddenly see owner-only management controls that `403` (`GET /api/lists/[id]/watchers` is owner-only). The org side already avoids this by carrying the role in the model.

**Fix:** Add an owner/role field to `UserList` (e.g. `myRole: WatcherRole?` or `isOwner: Bool`) and gate the management toolbar on it — even though it's harmless today, it future-proofs the surface and lets you drop the "presented from a list the user owns" assumption documented at `WatchersListView.swift:8-10`.

**Shipped (`179889a`, PR #20):** `UserList` now decodes `ownerId` and exposes `isOwned(by:)` (`Models/List.swift:272`), which treats a missing `ownerId` as owned so owner-scoped screens keep working on endpoints that omit it. `ListsView.swift:378` gates the management toolbar on `list.isOwned(by: authState.user?.id)`.

---

### G5 — Free owners over-restricted from removing document collaborators (Low, inverse gap) — ✅ FIXED

`DocumentCollaboratorsView.canManage = isSubscriber` (`:23`) hides **Remove** (`:82-90`) as well as Add/role-change. But the backend only subscriber-gates *add* and *role-change* — an **owner can remove a collaborator regardless of subscription** (DELETE is owner-only, not subscriber-gated).

**Impact:** a lapsed/non-subscribing document owner **cannot remove a collaborator in-app** — a case of denying access the user *does* have. They'd have to use the web.

**Fix:** Split the gate — `Remove` on `isOwner` (always, for an owned doc), `Add`/`role-change` on `isSubscriber`.

**Shipped (`a284d60`, PR #21):** the gate is split in `DocumentCollaboratorsView.swift` — `canManage` (`:24`) still requires a subscription for Add and role-change, while `canRemove` (`:28`) is available to the owner regardless of subscription, matching the owner-only-but-not-subscriber-gated DELETE.

---

### G6 — Email-verification gating coverage is uneven (Low) — ✅ FIXED

Cleared-status gating is applied in some places but not others:

- **Gated:** posting (post button disabled — `ComposeView.swift:152`, footer `:154-157`); DM attachments (`DMThreadView.swift:37` — `canAttach = emailVerified`).
- **Not pre-gated:** the subscriber compose **media controls** are shown to a subscriber with **unverified** email, but `POST /api/messages/{images,videos}/upload` requires verified email → `403`. That lands in `uploadVideo`'s generic catch (`ComposeView.swift:662-670`) as a generic failure.

**Impact:** minor — a subscriber-but-unverified user can start an image/video upload that fails late instead of the control being hidden/disabled up front.

**Fix:** Fold `isEmailVerified` into the media entry-point gates (image/video pickers), consistent with the post button.

**Shipped (`f772fd1`, PR #22):** `ComposeView.canAttachMedia` (`:80`) is now `canUseSubscriberFeatures && isEmailVerified`, so the image/video pickers are hidden for a subscriber with an unverified email instead of failing late with a 403.

---

### G7 — `WatchersListView` 401 handling deviates from the app's 401 contract (Low, robustness) — ✅ FIXED

`changeRole` and `remove` in `WatchersListView.swift:101-124` catch only `APIError.server` and the generic case — they **do not** catch `APIError.status(401)` and route it through `authState.handleUnauthorized()`. This violates the documented 401 contract (`CLAUDE.md`: "Don't log out on a feature-endpoint 401 — route through `handleUnauthorized()`"). Every other management view (`DocumentCollaboratorsView`, `OrganizationMembersView`, `ShareLinksSheet`, `ShareInvitesSheet`) handles it.

**Fix:** Add `catch APIError.status(401) { authState.handleUnauthorized() }` to both methods.

**Shipped (`d4c5fd6`, PR #23):** `WatchersListView` routes 401s through `authState.handleUnauthorized()` in all four mutating paths (`:104`, `:117`, `:131`, `:296`), restoring the documented 401 contract.

---

## 4. What's implemented correctly (keep / use as the pattern)

- **Server-side enforcement is complete** (§2). No client gap here is a data-exposure vulnerability.
- **Org role management is the reference implementation.** `OrganizationMembersView.canManage(_:)` (`Views/OrganizationsView.swift:230-235`) checks `myRole >= .admin`, refuses to demote the **last owner**, and blocks admins from managing owners. The model carries the role (`Organization.userRole` → `OrgRole`), so gating is data-driven, not navigation-assumed. **This is the pattern the list/document sharing surfaces (G1, G4) should adopt.**
- **Share-link / invite creation is hidden, not paywalled**, while view/revoke stays available to any owner (`ShareLinksSheet.swift:70`, `ShareInvitesSheet.swift:82`). Correct "free-app" posture.
- **Compose subscriber features are hidden entirely** (no disabled-but-tappable controls, no IAP steering) — `ComposeView.swift:60-66,104,127`. Matches the documented iOS-free-app direction.
- **Lists tab is owner-scoped** (`GET /api/lists` returns owned-only), which is why G4 is latent rather than live.
- **Compose org-author picker is role-filtered** to owner/admin before posting-as-org (`ComposeView.swift:558-565`), matching the backend's `role in ['owner','admin']` check.
- **Public browse surfaces are read-only** (`PublicListDetailView`, `PublicDocumentsView`); access to private content is deferred to the server.

---

## 5. Prioritized remediation

**All seven landed 2026-08-15, merged 2026-08-16 (PRs #17–#23), one PR per gap.** Nothing on this list is open.

| Priority | Gap | Action | Effort | Status |
|----------|-----|--------|--------|--------|
| 1 | **G1** | Add `isSubscriber` gate to `WatchersListView` Add button + role menu (mirror `DocumentCollaboratorsView`) | S | ✅ `65169a9` · PR #17 |
| 2 | **G3** | Introduce typed `APIError.forbidden`; map subscriber/authorization 403s to neutral in-app copy; drop dead `.status(403)` branches | S–M | ✅ `eb6b964` · PR #19 |
| 3 | **G2** | Refresh `authState.user` on `scenePhase == .active` and after web billing links | S | ✅ `0fa483a` · PR #18 |
| 4 | **G5** | Split document-collaborator gate: `Remove` on owner, `Add`/role-change on subscriber | S | ✅ `a284d60` · PR #21 |
| 5 | **G6** | Gate compose media pickers on `isEmailVerified` too | S | ✅ `f772fd1` · PR #22 |
| 6 | **G7** | Route `WatchersListView` 401s through `handleUnauthorized()` | XS | ✅ `d4c5fd6` · PR #23 |
| 7 | **G4** | Add owner/role field to `UserList`; gate `ListDetailView` management toolbar on it (future-proofing) | M | ✅ `179889a` · PR #20 |

**Bottom line:** No user can *obtain* data or actions the backend doesn't authorize — the server gates every axis. The work here was making the client's affordances match entitlement **consistently** (G1), keep entitlement **fresh** (G2), and present authorization failures **cleanly and store-safely** (G3) — **all done**.

### Residual verification (not a gap, a coverage note)

The **free-user gating path has still never been observed live**: the only test
account (`messenger`) is a subscriber, so every 💲 403 branch above is verified by
source reading and unit tests, not by a live non-subscriber session. A one-off probe
with a free account would close the last observational hole. Carried in
`the-gaps.md` → Part VII as well.
