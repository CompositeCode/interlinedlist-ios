# App Store Deployment — Pre-Flight Checklist

Last updated: 2026-07-08

---

## Feature gates

- [x] Phase 0.5 — Info.plist hygiene done (`ITSAppUsesNonExemptEncryption`, `arm64`, icon)
- [x] Phase 9 — Push notifications wired (PushService, register/unregister, `aps-environment: development` entitlement in place; Xcode auto-signing upgrades to production on archive)
- [x] Phase 14 — UGC safety shipped (report message/user, block/unblock, mute, terms gate on register, blocked users in settings)
- [x] Unit tests — All 8 moderation API methods have bearer token + 401 error tests; `ModerationModelTests` covers `BlockedUser`/`MutedUser` Codable decoding

---

## Accounts & credentials

| Item | Status | Notes |
|---|---|---|
| Apple Developer Program membership active; agreements accepted in ASC | ☐ | $99/yr — verify at developer.apple.com |
| Your role on team `BJA9558E4B` is Admin or App Manager | ☐ | Check in App Store Connect |
| APNs Auth Key (.p8) created, Key ID recorded, handed to backend | ☐ | Portal → Certificates, IDs & Profiles → Keys → enable APNs; one-time download |
| Demo reviewer account registered and confirmed working on production | ☐ | Register at interlinedlist.com with email/password; keep creds in password manager |
| Privacy Policy URL live | ✅ | `https://interlinedlist.com/privacy` → 200 (verified 2026-07-07) |
| Support URL live | ✅ | `https://interlinedlist.com/help` → 307 redirect (acceptable for ASC) |
| Community Guidelines / EULA URL live and linked from `RegisterView` | ✅ | `https://interlinedlist.com/terms` → 200 (verified 2026-07-07) |

---

## Xcode project

| Item | Status | Notes |
|---|---|---|
| App ID `com.interlinedlist.app` registered in portal with Push Notifications enabled | ☐ | Portal → Identifiers → App IDs |
| Automatic signing, team `BJA9558E4B`, archive signs cleanly | ☐ | Target → Signing & Capabilities |
| No unused capabilities or entitlements | ☐ | Only `aps-environment` is present |
| Build number incremented from any prior upload | ☐ | `agvtool next-version -all` |

---

## App Store Connect record

| Item | Status | Notes |
|---|---|---|
| App record created (name: InterlinedList, bundle ID, SKU: `interlinedlist-ios`, Full access) | ☐ | appstoreconnect.apple.com → Apps → "+" |
| Free pricing, all territories selected | ☐ | Pricing and Availability tab |
| Primary category: Social Networking | ☐ | App Information tab |
| Privacy Policy URL entered | ☐ | `https://interlinedlist.com/privacy` |
| Support URL entered | ☐ | `https://interlinedlist.com/help` |
| Age rating questionnaire completed | ☐ | Fill after Phase 14 confirmed — expected 17+ |

---

## Assets

| Item | Status | Notes |
|---|---|---|
| App icon: no empty wells, no alpha channel (verified in Xcode asset catalog) | ☐ | `InterlinedList/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |
| Screenshots: 6.9" set uploaded (iPhone 16 Pro Max, 1320 × 2868 px) | ☐ | Minimum screens: Feed, Compose, Lists, Profile, Settings |
| Screenshots: 6.5" set uploaded (iPhone 15 Plus, 1242 × 2688 px) | ☐ | Same minimum screens |
| App name (≤30 chars): "InterlinedList" | ☐ | Verify uniqueness in ASC at record creation |
| Subtitle (≤30 chars) | ☐ | e.g. "Social lists, shared" |
| Description (≤4,000 chars) | ☐ | |
| Keywords (≤100 chars total, comma-separated) | ☐ | |
| Promotional text (≤170 chars) | ☐ | Changeable without a new submission |
| What's New: "Initial release." | ☐ | |
| App Privacy nutrition label completed and saved in ASC | ☐ | See §4 in `App-Store-Deployment.md` for declared data types |

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
- [ ] OAuth (at least one provider — Mastodon or Bluesky)
- [ ] Compose + post (text, image)
- [ ] Feed scroll, dig/undig, reply
- [ ] Lists and Documents CRUD
- [ ] Organizations list loads (Bearer auth fix shipped 2026-07-07)
- [ ] Deep-link callbacks (`interlinedlist://reset-password`, `interlinedlist://verify-email`)
- [ ] Push notification receipt and tap routing
- [ ] Settings, sign-out, delete-account flow
- [ ] Report a message (tap `...` on any post → Report)
- [ ] Block a user (tap `...` on any post or visit their profile → Block)

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
