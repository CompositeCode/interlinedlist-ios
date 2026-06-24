# subscription-permissions-update — direction change

**Date:** 2026-06-24
**Status:** Pending review. Do not act on this doc until signed off.

## The new principle

The iOS app is a **free** app. **No subscription UI, no billing UI, no paywall
copy, no "subscribe" call-to-action appears anywhere in the iOS app.**

- **Free features** are visible to every authenticated user.
- **Subscriber-only features** are visible **only** when the logged-in
  user's `customerStatus` indicates an active subscription. To free
  users, those features simply **do not exist** — no button, no menu
  item, no toggle, no error message about subscriptions.
- All subscription management (sign-up, upgrade, billing, plan changes,
  cancellation) happens **on the web** at `interlinedlist.com`. The iOS
  app never links to it, never opens it via `SFSafariViewController`,
  never mentions it.

### Why this matters

1. **App Store rules.** Apple's guideline 3.1.3(a) requires that
   digital-goods sales go through Apple's In-App Purchase. By having
   zero subscription surface in iOS, we don't bump into that rule at
   all — no review risk.
2. **Simpler app.** No paywall flows, no plan-catalog endpoint, no
   Stripe handoff, no "manage subscription" screen. The whole Phase 3
   "subscriber CTA" track disappears.
3. **The website is the source of truth** for commerce. Users who want
   to upgrade do it where they already have a browser session, payment
   method on file, etc.

## What this changes from the current plan

### Roadmap docs (`GAP-NEXT-STEPS.md`, `GAP-ENDPOINTS.md`)

- `GAP-NEXT-STEPS.md` Phase 3 — **drop "Subscriber CTA" item entirely.**
  Phase 3 keeps avatar upload, orgs lookup, delete account; that's it.
- `GAP-NEXT-STEPS.md` Phase 4 — change "disable + show paywall" pattern
  to "**hide entirely**." Cross-post toggles, schedule picker, image/
  video pickers all disappear from the compose UI for non-subscribers.
  No paywall message, no disabled-but-tappable state.
- `GAP-NEXT-STEPS.md` Phase 12 (Settings) — **drop "Subscription status
  + manage subscription" row entirely.** No row, no link-out.
- `GAP-ENDPOINTS.md` §B1 — **delete the gap.** We no longer need a
  `/api/subscriptions/plans` endpoint from the backend because we'll
  never render plan info on iOS.
- `GAP-ENDPOINTS.md` summary table — remove the "Subscriptions (Stripe)"
  row, or mark as "intentionally not used by iOS."

### Code that exists today and needs to change

The audit found subscription-aware copy / handling in **6 files**.
Each needs to change from "show paywall" → "hide feature."

| File:line | Today | New direction |
|---|---|---|
| `Views/ListsView.swift:215, 223–224` | Static `paywallMessage = "Creating folders requires a subscription. You can subscribe at interlinedlist.com."` shown on 403 from `POST /api/folders` | **Hide the "New Folder" button entirely** when `authState.user?.isSubscriber != true`. Drop the `paywallMessage` constant. Keep the 403 catch arm but surface a generic "Couldn't create folder" — the button shouldn't have been reachable anyway. |
| `Views/ComposeView.swift:170–193` | Cross-post buttons (`M`/`BS`/`in`) rendered as `.disabled(true)` placeholders, visible to everyone | **Wrap the cross-post HStack** in `if user.isSubscriber { ... }`. Same for the X button to be added in Phase 4. |
| `Views/ComposeView.swift:138–169` | Image (`PhotosPicker`) + video pickers rendered to everyone, fail on upload with 403 | **Wrap each picker** in `if user.isSubscriber { ... }`. Don't render the picker for free users. |
| `Views/ComposeView.swift:297, 314` | Hardcoded strings `"Video upload requires an active subscription."` / `"Image upload requires an active subscription."` on 403 | **Delete these branches** — pickers are now hidden for free users, so 403 isn't reachable from normal flow. Generic "Upload failed" handles the unexpected case. |
| `Views/DocumentsView.swift:527, 625` | `errorMessage = "Requires active subscription."` on 403 from document folder create/update | **Hide "Create folder" / "Move to folder" UI** for free users. Same generic error fallback for the unreachable case. |
| `Views/ScheduledMessagesView.swift:78` | `errorMessage = "Scheduled posts require an active subscription."` on 403 | **Hide the calendar/schedule entry point in `FeedView.swift:200–201`** for free users. The `ScheduledMessagesView` itself never renders for them. Schedule-time picker in `ComposeView` likewise hidden. |
| `Views/FeedView.swift:200–201` | Calendar toolbar button always visible | Wrap in `if user.isSubscriber { ... }` so the entry point disappears. |
| `Services/AppDataStore.swift:95–96` | On 403 from documents: `documentsError = "Requires active subscription."` | **Stay silent on 403.** Free users have full documents access — a 403 here would mean something else broke. Surface as a generic load failure. |
| `Views/NotificationsView.swift:104` | Already silent on subscriber-only endpoint failure | **Leave as-is** — already follows the new pattern. |

### Wire model — no changes needed

- `User.customerStatus: String?` and `User.isSubscriber: Bool` stay
  exactly as they are. They're the input to the new visibility gates.

### Tests to update

| Test file | Change |
|---|---|
| `APIClientListFolderTests.test_createListFolder_subscriberOnly403_surfacesServerMessageVerbatim` | Keep — verifies the client-side error decoding still works. The fact that the button is hidden in the UI doesn't invalidate the network-layer contract. |
| `APIClientVideoUploadTests` (subscriber 403 case) | Same — keep. |
| `UserModelTests.test_isSubscriber_*` (5 cases) | Keep — `isSubscriber` is now the only gating predicate; coverage stays valuable. |
| New tests to add | `ListsView_hidesCreateFolderButtonForFreeUser` style — but these are SwiftUI view tests, which we don't have infrastructure for. Verify visibility via the existing `ListSchemaDraft` refactor pattern: extract visibility predicates if needed, unit-test those. |

## Subscriber-only feature inventory

Cross-referenced from `/help/api` docs. iOS will gate visibility on
each of these by `authState.user?.isSubscriber == true`:

| Feature | Endpoint | Today's iOS surface | New behavior |
|---|---|---|---|
| Create list folder | `POST /api/folders` | "New Folder" button + paywall on 403 | Button hidden |
| Update / delete list folder | `PUT/DELETE /api/folders/:id` | Edit / delete actions | Hidden (only folders user created exist; degraded subscribers see them but can't edit) |
| Create document folder | `POST /api/documents/folders` | Same as list folder | Same — hidden |
| Image upload | `POST /api/messages/images/upload` | Picker visible to all | Picker hidden |
| Video upload | `POST /api/messages/videos/upload` | Same | Same — hidden |
| Scheduled post | `scheduledAt` on `POST /api/messages` + `/api/messages/scheduled` | Calendar button in FeedView toolbar + sheet | Hidden |
| Edit scheduled post | `PATCH /api/messages/:id` | Phase 4 (not yet built) | Build with hide-not-disable from day one |
| Cross-post to Mastodon | `mastodonProviderIds[]` | Disabled placeholder | Hidden |
| Cross-post to Bluesky | `crossPostToBluesky` | Disabled placeholder | Hidden |
| Cross-post to LinkedIn | `crossPostToLinkedIn` | Disabled placeholder | Hidden |
| Cross-post to X | `crossPostToTwitter` | Not built yet | Build with hide-not-disable |
| Folder-based document `folderId` move | `PATCH /api/documents/:id` with `folderId` | Move-to-folder UI | Hidden (no folders to move into for free users) |

## Edge cases

### 1. Degraded subscribers (was paid, now free)

A user could have created folders, scheduled posts, or set up
cross-posting while subscribed, then let their subscription lapse. The
server still has their data.

**Default behavior:** their existing folders/scheduled posts/etc.
still render (read-only or view-only). They just can't create new ones.

This needs explicit decisions:

- **Existing folders:** show them in the tree (they're returned by
  `GET /api/folders`). Allow rename/delete? Or just show?
  **Recommendation:** show as read-only — they can move lists out and
  delete the folder once empty. No "rename" UI for free users.
- **Scheduled posts:** the calendar button is hidden, so they can't
  reach the scheduled view from the UI. But scheduled posts will still
  fire on the server. **Recommendation:** that's fine — the server
  honors what was already scheduled.
- **Existing cross-post connections:** identities are linked at the
  account level (`/api/user/identities`). They stay linked but can't
  be triggered for new posts. **Recommendation:** Phase 2 identity
  management UI gates linking new ones on subscriber status too; the
  list itself is informational.

### 2. Unauthenticated state

Doesn't matter — login is required for almost everything anyway. The
visibility gate is `authState.user?.isSubscriber == true`, which is
`false` for nil user.

### 3. Server changes `customerStatus` mid-session

`AuthState` refreshes the user on launch and on certain events. The UI
re-evaluates `isSubscriber` on every view body re-render, so the gates
re-apply automatically when `@EnvironmentObject` updates.

### 4. Network flake — user object can't be fetched

`authState.user` is nil. Subscriber gates evaluate false. User sees
free features only. If they were a subscriber, they're temporarily
demoted UI-wise — acceptable for transient state; on next successful
`currentUser()` the gates re-open.

### 5. App Store review angle

The simpler the iOS app's relationship to subscriptions, the lower the
review risk. The cleanest stance for review notes if asked:
> "InterlinedList iOS is a free companion app to a web service. Some
> advanced features are unlocked for users who have an active
> subscription managed entirely on the web at interlinedlist.com. The
> iOS app does not sell, offer, or link to any subscription, and does
> not display pricing or sign-up flows."

That stance is **trivially true** under the new direction — there's
literally nothing subscription-related in the iOS bundle to review.

## What this means for the immediate roadmap

### Phase 1 (already shipped)

- Most of Phase 1 is fine. **One change**: `ListsView` paywall message
  needs to be removed and the "New Folder" button gated. Small follow-up.
- `User.customerStatus` decoding stays. `isSubscriber` predicate stays.
- The 403 paywall test in `APIClientListFolderTests` stays (verifies
  network-layer error decoding).

### Phase 2 (auth surface — about to dispatch)

- No changes. Auth flows aren't subscription-aware.

### Phase 3 (profile / account management)

- **Drop the "Subscriber CTA on profile" item.**
- Keep: avatar upload, orgs lookup, delete account.
- Net result: Phase 3 becomes even smaller than originally planned.

### Phase 4 (compose parity)

- All subscriber-only controls (cross-post, scheduling, image/video
  pickers) **hide for free users** instead of disable+paywall.
- Remove the "show paywall message style" criterion.
- Net result: simpler, fewer states to design.

### Phase 12 (Settings)

- Drop the "Subscription status + manage subscription" row.
- Net result: smaller Settings screen.

### Backend gap §B1

- **Delete.** No `/api/subscriptions/plans` endpoint needed from
  backend. Lower the backend team's pending-asks pile.

## Open questions for the user

1. **Degraded-subscriber UX**: confirm the recommendation above
   (existing folders show read-only, scheduled posts honor on server,
   linked identities stay linked but new cross-posts blocked). Or
   different stance?
2. **Empty-state copy when a free user looks at a screen that USED to
   show subscriber features**: for example, if we hide the "New Folder"
   button entirely, do we want any text explaining "Folders are
   available with a subscription, manage at interlinedlist.com" — or
   pure silence (the principle of "the feature doesn't exist")? The
   strict reading of the new principle says silence; some users may be
   confused.
3. **Settings → About / Help links**: still appropriate to link out to
   `interlinedlist.com/help/*` etc. via `SFSafariViewController`?
   That's not commerce, but it is "web app handles X." Probably yes,
   but worth confirming.
4. **Onboarding / first-launch screen**: when a brand-new user opens
   the iOS app, do we want any "to upgrade visit interlinedlist.com"
   text anywhere — first-launch tooltip, About screen — or zero
   mentions anywhere in the bundle? Strict reading: zero.

## Suggested execution order once approved

1. **Update roadmap docs first** (`GAP-NEXT-STEPS.md` and
   `GAP-ENDPOINTS.md`) to match this direction. One commit.
2. **Phase 1 cleanup** — remove `ListsView` paywall string, hide "New
   Folder" button for free users. One commit.
3. **Phase 4 prep pass** — even though we're not building Phase 4
   yet, hide the image/video pickers and the calendar button **now**
   so the app stops surfacing 403s to free users. One commit.
4. **Delete the now-unreachable error branches** in `DocumentsView`,
   `ComposeView`, `ScheduledMessagesView`, `AppDataStore`. One commit.
5. *Then* dispatch Phase 2 + Phase 3 (revised) as parallel sub-agents.
