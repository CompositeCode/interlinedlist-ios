# App Store Deployment — Pre-Flight Checklist

Last updated: 2026-09-05

**Where we are:** iOS engineering for v1 is **done** — every deployment phase plus the
whole `the-gaps.md` parity backlog and the `the-gaps-access.md` access remediation have
shipped, and the last verification run was **823 unit tests, 0 failures, build green**
(E2E excluded). **Everything below that's still unchecked is submission logistics, not
code.** Full procedure for each item lives in `App-Store-Deployment.md`.

**Critical path:** Apple portal (App ID + Push + Associated Domains → regen profile) →
APNs `.p8` → demo account → ASC record + listing copy + privacy label → screenshots →
build bump → archive → TestFlight device smoke test → submit.

---

## Feature gates

- [x] Phase 0.5 — Info.plist hygiene done (`ITSAppUsesNonExemptEncryption`, `arm64`, icon)
- [x] Phase 9 — Push notifications wired (PushService, register/unregister, `aps-environment: development` entitlement in place; Xcode auto-signing upgrades to production on archive)
- [x] Phase 14 — UGC safety shipped (report message/user, block/unblock, mute, terms gate on register, blocked users in settings)
- [x] Phases 10, 11, 13b, 15, 16 shipped (doc inline images, GitHub integration, tag discovery, post-as-org, offline document sync)
- [x] `the-gaps.md` parity backlog closed — D1–D3, G1–G10, G12–G14 (G11 document presence is the only deliberate deferral)
- [x] `the-gaps-access.md` G1–G7 access-control remediation shipped (PRs #17–#23)
- [x] Unit tests — full suite green: **823 tests, 0 failures** (2026-09-05, `-skip-testing:InterlinedListTests/E2EReadOnlyTests`)

---

## Accounts & credentials

| Item | Status | Notes |
|---|---|---|
| Apple Developer Program membership active; agreements accepted in ASC | ☐ | $99/yr — verify at developer.apple.com |
| Your role on team `BJA9558E4B` is Admin or App Manager | ☐ | Check in App Store Connect |
| APNs Auth Key (.p8) created, Key ID recorded, handed to backend | ☐ | Portal → Certificates, IDs & Profiles → Keys → enable APNs; one-time download |
| Demo reviewer account registered and confirmed working on production | ☐ | Register at interlinedlist.com with email/password; keep creds in password manager |
| Privacy Policy URL live | ✅ | `https://interlinedlist.com/privacy` → 200 (re-verified 2026-09-05) |
| Support URL live | ✅ | `https://interlinedlist.com/help` → 200 (re-verified 2026-09-05; was a 307 in July) |
| Community Guidelines / EULA URL live and linked from `RegisterView` | ✅ | `https://interlinedlist.com/terms` → 200 (re-verified 2026-09-05) |
| Universal Links AASA served + cached by Apple | ✅ | `/.well-known/apple-app-site-association` → 200 `application/json`, `appID: BJA9558E4B.com.interlinedlist.app`; Apple CDN copy → 200 (verified 2026-09-05) |

---

## Xcode project

| Item | Status | Notes |
|---|---|---|
| App ID `com.interlinedlist.app` registered in portal with Push Notifications enabled | ☐ | Portal → Identifiers → App IDs |
| **Associated Domains enabled on the App ID + provisioning profile regenerated** | ☐ | The entitlement (`applinks:interlinedlist.com`) is already in `InterlinedList.entitlements` and the backend AASA is live — **without the portal capability the archive won't provision** |
| Automatic signing, team `BJA9558E4B`, archive signs cleanly | ◑ | Config verified 2026-09-05 (`CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM=BJA9558E4B`, bundle id `com.interlinedlist.app`, iOS 17.0, `TARGETED_DEVICE_FAMILY=1`, `ITSAppUsesNonExemptEncryption=false`, `arm64`). The **archive itself hasn't been run** — it needs the portal capabilities first |
| No unused capabilities or entitlements | ✅ | Verified 2026-09-05 — exactly two: `aps-environment` and `com.apple.developer.associated-domains` |
| Build number incremented from any prior upload | ☐ | Currently `MARKETING_VERSION 1.0` / `CURRENT_PROJECT_VERSION 1`, never uploaded — `agvtool next-version -all` before each upload |

---

## App Store Connect record

| Item | Status | Notes |
|---|---|---|
| App record created (name: InterlinedList, bundle ID, SKU: `interlinedlist-ios`, Full access) | ☐ | appstoreconnect.apple.com → Apps → "+" |
| Free pricing, all territories selected | ☐ | Pricing and Availability tab |
| Primary category: Social Networking | ☐ | App Information tab |
| Privacy Policy URL entered | ☐ | `https://interlinedlist.com/privacy` |
| Support URL entered | ☐ | `https://interlinedlist.com/help` |
| Age rating questionnaire completed | ☐ | UGC social app with report/block/mute shipped — expected 17+ |

---

## Assets

*Listing copy, privacy-label answers, age-rating answers, and review notes are all
drafted in **`App-Store-Listing-Copy.md`** — paste them straight into ASC.*

| Item | Status | Notes |
|---|---|---|
| App icon: no empty wells, no alpha channel | ✅ | **Fixed 2026-09-05** — `AppIcon-1024.png` shipped as RGBA (fully opaque, but Apple rejects any alpha: ITMS-90717). Re-saved as RGB, pixels unchanged. The dark-appearance variant keeps its alpha, which Apple expects |
| Screenshots: 6.9" set captured (iPhone 16 Pro Max, 1320 × 2868 px) | ☐ | **Blocked on a logged-in session** — capture pipeline verified end to end (app installs, launches, `xcrun simctl io … screenshot` yields exactly 1320 × 2868), but this session has no simulator tap/type tooling, so the app can't be driven past the login screen. Use the `qa-screenshotter` agent or drive it by hand. Screens: Feed, Compose, Lists, Profile, Settings |
| Screenshots: 6.5" set captured (1242 × 2688 px) | ☐ | Same blocker. **Note: iPhone 15 Plus is 1290 × 2796, not 6.5"** — the earlier note in this file was wrong. A correct 6.5" device is provisioned: **`IL-6.5in-11ProMax`** (iPhone 11 Pro Max on iOS 17.5, UDID `C272D802-6737-46CC-A943-87C80749FF67`), verified to render at 1242 × 2688 |
| App name (≤30 chars): "InterlinedList" | ☐ | Verify uniqueness in ASC at record creation |
| Subtitle (≤30 chars) | ✅ drafted | "Social lists, shared" (20) — `App-Store-Listing-Copy.md` |
| Description (≤4,000 chars) | ✅ drafted | 1,944 chars, no billing language — `App-Store-Listing-Copy.md` |
| Keywords (≤100 chars total, comma-separated) | ✅ drafted | 90 chars — `App-Store-Listing-Copy.md` |
| Promotional text (≤170 chars) | ✅ drafted | 142 chars — `App-Store-Listing-Copy.md` |
| What's New: "Initial release." | ✅ drafted | `App-Store-Listing-Copy.md` |
| App Privacy nutrition label completed and saved in ASC | ✅ drafted | Audited against `APIClient` bodies 2026-09-05; adds **Photos/Videos** and **Search History**, which the old table missed — `App-Store-Listing-Copy.md` |
| Privacy usage-description strings in `Info.plist` | ✅ n/a | Verified 2026-09-05: media comes only from SwiftUI `PhotosPicker` (out-of-process), and there is no camera, location, contacts, or microphone use — **no usage-description strings required** |

---

## Upload & review

| Item | Status | Notes |
|---|---|---|
| Build archived (Release, Any iOS Device / arm64) | ☐ | Product → Archive in Xcode |
| Build uploaded and processed (visible in TestFlight) | ☐ | Distribute App → App Store Connect → Upload |
| TestFlight smoke-test passed on a real device | ☐ | See smoke-test checklist below |
| Review notes written | ☐ | See review notes template below |
| Submit for Review | ☐ | |

### Smoke-test checklist (real device, before submitting)

- [ ] Email/password login and registration
- [ ] OAuth (at least one provider — Mastodon or Bluesky); GitHub linking via the mobile OAuth branch
- [ ] Compose + post (text, multi-image); trending-tag strip and live link preview
- [ ] Feed scroll, dig/undig, reply
- [ ] Lists and Documents CRUD; document inline image upload
- [ ] Direct Messages — inbox, open a thread, send, unread badge *(the recipient-tap fix from 2026-07-31 has never been re-driven by hand — exercise it here)*
- [ ] Sharing — create/copy/revoke a share-link; open a shared list/document link
- [ ] GitHub-backed list — add, close, and reopen an issue; confirm the list refreshes
- [ ] Offline document sync — edit in airplane mode, reconnect, confirm the edit persists
- [ ] Organizations list loads; post as an organization
- [ ] Deep-link callbacks (`interlinedlist://reset-password`, `interlinedlist://verify-email`)
- [ ] Universal Links — tap an `https://interlinedlist.com/user/...` link and confirm it opens in-app
- [ ] Push notification receipt and tap routing
- [ ] Settings, sign-out, delete-account flow
- [ ] Report a message (tap `...` on any post → Report)
- [ ] Block a user (tap `...` on any post or visit their profile → Block)
- [ ] **Free (non-subscriber) account** — premium controls are hidden (not paywalled) and no upsell copy appears anywhere *(never yet exercised live; the only test account is a subscriber)*

### Review notes template

```
Demo login:
  Email:    <demo-account-email>
  Password: <demo-account-password>

Subscriptions are managed exclusively at interlinedlist.com.
There is no in-app purchase, paywall, or billing UI in this app.

To delete the account: Profile → Edit Profile → Delete Account (double-confirm).

To report content: tap the … menu on any post → Report.
To block a user: tap the … menu on any post or visit their profile → Block.
```
