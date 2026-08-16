# the-gaps-access.md — Access-Control Gap Analysis

**Scope:** Does a user only get the things they have access to based on **subscription**, **role**, or **approved/cleared status**? This reviews the iOS client (`InterlinedList/`) and cross-references the backend at `~/Codez/interlinedlist/` for the source-of-truth enforcement.

**Date:** 2026-08-15 · **Reviewer:** automated audit (Claude)

---

## 1. Executive summary

**The backend enforces every access rule server-side** (verified — see §2). Non-subscribers, non-owners, wrong-role users, and unverified-email users all receive `403 Forbidden` from the API regardless of what the app does. **There is no unauthorized-data-exposure vulnerability here.** Defense-in-depth is intact.

The gaps are therefore **client-side correctness / consistency / UX**, plus **one App Store-review risk**:

- The client uses three separate access axes — **subscription** (`isSubscriber`), **role** (`OrgRole`, `WatcherRole`), and **cleared status** (`emailVerified`) — but applies them **inconsistently**. One premium surface (list-watcher management) isn't gated at all, while its exact twin (document collaborators) is.
- Entitlement state (`customerStatus`) is **cached and rarely refreshed**, so it goes stale when the subscription changes on the web (where billing lives).
- Authorization `403`s surface the **raw backend message**, and the app's intended friendly/typed 403 handling is **dead code** — a correctness bug and a potential IAP-steering issue if that text contains upsell copy.

None of these leak data. All of them can make a paying/entitled user see the wrong thing, or make a non-entitled user tap controls that always fail.

### Severity legend
Severity reflects **product/UX correctness and store-review risk**, not data security (all paths are server-enforced).

| ID | Gap | Severity |
|----|-----|----------|
| G1 | List-watcher management not subscriber-gated (inconsistent with documents) | **Medium** |
| G2 | Stale subscription/entitlement state — no refresh on foreground | **Medium** |
| G3 | Authorization 403s surface raw backend text; friendly/typed handling is dead code | **Medium** (store-review) |
| G4 | Client can't distinguish owned vs shared lists (`UserList` has no owner/role field) | **Low** (latent) |
| G5 | Free owners over-restricted from removing document collaborators | **Low** |
| G6 | Email-verification gating coverage is uneven (media upload not pre-gated) | **Low** |
| G7 | `WatchersListView` 401 handling deviates from the app's 401 contract | **Low** |

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

### G1 — List-watcher management is not subscriber-gated (Medium)

**The app gates the identical feature two different ways.** Document collaborators, share-links, and share-invites all hide their *create* controls for non-subscribers:

- `Views/DocumentCollaboratorsView.swift:23` — `canManage = authState.user?.isSubscriber == true` (hides Add + role menu + remove).
- `Views/ShareLinksSheet.swift:29` — `canCreate = isSubscriber` (hides "Create link").
- `Views/ShareInvitesSheet.swift:33` — `canInvite = isSubscriber` (hides "Send invite").

But **`Views/WatchersListView.swift` has no subscriber gate at all.** The "Add watcher" toolbar button (`:45-48`) is always shown, and the role-change `Menu` (`:142-161`) is always active. The backend requires a subscription for `POST /api/lists/[id]/watchers` (named user) and `PUT /api/lists/[id]/watchers/[userId]`.

**Impact:** A non-subscribing **owner** of a list (the Lists tab shows only owned lists — see §4) sees a fully functional-looking watcher manager. Every "add" (`WatchersListView.swift:280-291`) and every role change (`:101-112`) returns `403`, and the error path surfaces the **raw backend message** (`self.error = msg`). Confusing, and off-brand versus the rest of the app which hides-not-paywalls.

**Fix:** Mirror `DocumentCollaboratorsView`: introduce `canManage = authState.user?.isSubscriber == true`, gate the toolbar "Add watcher" button and the role-change menu on it. Viewing/removing existing watchers can stay available to any owner (the GET and DELETE are not subscriber-gated server-side).

---

### G2 — Stale subscription/entitlement state; no foreground refresh (Medium)

`isSubscriber` is derived from `User.customerStatus`, which is cached in `AuthState.user` and only re-fetched on:
- launch/login/OAuth (`Services/AuthState.swift:33,52,76`),
- `handleUnauthorized()` re-validation (`:126`),
- `refreshUser()` — which is **only called from the email-verify deep-link handlers** (`InterlinedListApp.swift:93,105`).

There is **no `scenePhase == .active` refresh** and no refresh before presenting premium UI. Per `CLAUDE.md`, subscriptions/sharing are managed on the **web** (iOS ships as a free app with no IAP).

**Impact:**
- **Cancel/refund/expiry on web** → the app keeps `isSubscriber == true`, keeps showing premium controls, and every premium action `403`s (into the raw-text path of G3) until the next relaunch/login.
- **Subscribe on web while the app is backgrounded** → the app keeps `isSubscriber == false` and keeps premium features hidden — the user paid but can't see what they bought until relaunch.

**Fix:** Refresh the user on foreground (`.onChange(of: scenePhase)` → `.active` → `authState.refreshUser()`), and immediately after returning from any web billing/settings link. Cheap `GET /api/user`; keeps entitlement fresh.

---

### G3 — Authorization 403s surface raw backend text; typed handling is dead code (Medium, store-review)

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

---

### G4 — Client can't distinguish owned vs shared lists (Low, latent)

`UserList` (`Models/List.swift:122-171`) carries **no `userId` / owner / role field**. `ListDetailView`'s toolbar shows **Manage watchers / Share / Invite** unconditionally (`Views/ListsView.swift:492-515`) with no ownership gate — it *can't* gate, because the model has no ownership signal.

**Currently masked:** `GET /api/lists` returns **owner-only** lists (verified: `getUserLists` filters by `userId` with no watcher/`OR` clause), so the Lists tab never contains shared-in lists and the toolbar is only ever seen by owners. **No live defect today.**

**Why it's still a gap:** it's a latent inconsistency. If the list index is ever broadened to include shared/watched lists (the self-watch-public-lists feature makes this plausible), non-owners would suddenly see owner-only management controls that `403` (`GET /api/lists/[id]/watchers` is owner-only). The org side already avoids this by carrying the role in the model.

**Fix:** Add an owner/role field to `UserList` (e.g. `myRole: WatcherRole?` or `isOwner: Bool`) and gate the management toolbar on it — even though it's harmless today, it future-proofs the surface and lets you drop the "presented from a list the user owns" assumption documented at `WatchersListView.swift:8-10`.

---

### G5 — Free owners over-restricted from removing document collaborators (Low, inverse gap)

`DocumentCollaboratorsView.canManage = isSubscriber` (`:23`) hides **Remove** (`:82-90`) as well as Add/role-change. But the backend only subscriber-gates *add* and *role-change* — an **owner can remove a collaborator regardless of subscription** (DELETE is owner-only, not subscriber-gated).

**Impact:** a lapsed/non-subscribing document owner **cannot remove a collaborator in-app** — a case of denying access the user *does* have. They'd have to use the web.

**Fix:** Split the gate — `Remove` on `isOwner` (always, for an owned doc), `Add`/`role-change` on `isSubscriber`.

---

### G6 — Email-verification gating coverage is uneven (Low)

Cleared-status gating is applied in some places but not others:

- **Gated:** posting (post button disabled — `ComposeView.swift:152`, footer `:154-157`); DM attachments (`DMThreadView.swift:37` — `canAttach = emailVerified`).
- **Not pre-gated:** the subscriber compose **media controls** are shown to a subscriber with **unverified** email, but `POST /api/messages/{images,videos}/upload` requires verified email → `403`. That lands in `uploadVideo`'s generic catch (`ComposeView.swift:662-670`) as a generic failure.

**Impact:** minor — a subscriber-but-unverified user can start an image/video upload that fails late instead of the control being hidden/disabled up front.

**Fix:** Fold `isEmailVerified` into the media entry-point gates (image/video pickers), consistent with the post button.

---

### G7 — `WatchersListView` 401 handling deviates from the app's 401 contract (Low, robustness)

`changeRole` and `remove` in `WatchersListView.swift:101-124` catch only `APIError.server` and the generic case — they **do not** catch `APIError.status(401)` and route it through `authState.handleUnauthorized()`. This violates the documented 401 contract (`CLAUDE.md`: "Don't log out on a feature-endpoint 401 — route through `handleUnauthorized()`"). Every other management view (`DocumentCollaboratorsView`, `OrganizationMembersView`, `ShareLinksSheet`, `ShareInvitesSheet`) handles it.

**Fix:** Add `catch APIError.status(401) { authState.handleUnauthorized() }` to both methods.

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

| Priority | Gap | Action | Effort |
|----------|-----|--------|--------|
| 1 | **G1** | Add `isSubscriber` gate to `WatchersListView` Add button + role menu (mirror `DocumentCollaboratorsView`) | S |
| 2 | **G3** | Introduce typed `APIError.forbidden`; map subscriber/authorization 403s to neutral in-app copy; drop dead `.status(403)` branches | S–M |
| 3 | **G2** | Refresh `authState.user` on `scenePhase == .active` and after web billing links | S |
| 4 | **G5** | Split document-collaborator gate: `Remove` on owner, `Add`/role-change on subscriber | S |
| 5 | **G6** | Gate compose media pickers on `isEmailVerified` too | S |
| 6 | **G7** | Route `WatchersListView` 401s through `handleUnauthorized()` | XS |
| 7 | **G4** | Add owner/role field to `UserList`; gate `ListDetailView` management toolbar on it (future-proofing) | M |

**Bottom line:** No user can *obtain* data or actions the backend doesn't authorize — the server gates every axis. The work here is making the client's affordances match entitlement **consistently** (G1), keep entitlement **fresh** (G2), and present authorization failures **cleanly and store-safely** (G3).
