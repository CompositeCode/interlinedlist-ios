# App Store Deployment — InterlinedList iOS

Single reference for getting the app from its current state to the App Store.
For the full context behind each item, see `GAP-APPLE.md`, `GAP-NEXT-STEPS.md`,
and `GAP-ENDPOINTS.md`. This document synthesises them into an actionable
submission checklist targeted at whoever is doing the work.

**App details at a glance**

| Field | Value |
|---|---|
| Bundle ID | `com.interlinedlist.app` |
| Version | `1.0` |
| Build | `1` (increment every upload) |
| Deployment target | iOS 17.0 |
| Device family | iPhone only |
| Team ID | `BJA9558E4B` |
| Signing | Automatic |
| URL scheme | `interlinedlist://` |
| Third-party SDKs | None (pure Apple frameworks) |

### Subscription & billing direction

The app is **free with no in-app purchase, subscription, or billing UI of any kind**. Subscriber-only features are silently hidden for non-subscribers — there is no "upgrade" call-to-action, no price text, and no link to `interlinedlist.com` to pay. Subscription management lives entirely on the web. This is the safe path for App Review (Guideline 3.1.1 / anti-steering): the build stays silent on billing. **Do not add any billing UI** — it would trigger immediate rejection.

---

## 0. What's Already Shipped

The following phases are complete and in the current build:

| Phase | Description | Shipped |
|---|---|---|
| 1 | Gap-closure + schema editor + subscriber awareness | 2026-06-23 |
| 2 | Auth surface parity — reset, verify, OAuth ×5, identity linking, email change | 2026-06-24 |
| 3 | Profile / account management — avatar upload + from-URL, organizations strip, delete-account | 2026-06-24 |
| B0 | Structured list-schema editing | 2026-06-25 |
| 4 | Compose feature parity — cross-post toggles, repost, edit scheduledAt, crossPostResults toast | 2026-06-25 |
| 5 | Follow surface parity — followers/following (paginated), mutual-count, remove-follower | 2026-06-25 |
| 6 | List collaboration / watchers — WatchersListView, roles, add/remove, Watch CTA | 2026-06-25 |
| 7 | Public browse — PublicListDetailView (read-only + Watch CTA), public documents + reader | 2026-06-25 |
| 8 | Organizations — CRUD, members, roles, join; post-as-org deferred to Phase 15 | 2026-06-25 |
| 12 | Settings panel — theme, default visibility, connected accounts, About, sign-out, notification preferences | 2026-06-25 |
| 13a | Feed search — `.searchable` → `GET /api/messages/search` | 2026-06-25 |

**What works today:** auth (email + OAuth ×5), feed (infinite scroll, dig, reply, search, link previews), compose (text/image/video, cross-post, repost, scheduled), lists (CRUD, folders, schema editor, watchers), documents (CRUD, folders, search, public reader), public browse, notifications (tray, preferences), profile, follow, organizations, settings, exports.

**Not yet built (remaining phases):** push notifications, inline document image upload, UGC moderation (report/block/mute/terms gate), post as org, offline document sync, realtime, GitHub integration, tag discovery.

---

## 1. Feature Completion — What Must Ship Before Submission

### Tier 0 — Hard ship-blockers (nothing uploads without these)

#### Phase 14 — UGC Safety & Moderation  `Large` ⛔
Apple Guideline 1.2 requires every UGC/social app to provide: (1) report
objectionable content, (2) block abusive users, (3) a posted community-
guidelines/zero-tolerance EULA accepted at registration, and (4) a developer
contact (the support URL covers this). **The app has none of 1–3 today.**

**Start with a backend discovery pass** — it is unconfirmed whether the
server exposes any of these endpoints. Probe and document in `GAP-ENDPOINTS.md §H`:

| Need | Candidate endpoint |
|---|---|
| Report a message | `POST /api/messages/{id}/report` or `POST /api/report` |
| Report a user | `POST /api/users/{id}/report` |
| Block a user | `POST /api/users/{id}/block` |
| Unblock a user | `DELETE /api/users/{id}/block` |
| List blocked users | `GET /api/blocks` or `GET /api/user/blocks` |
| Mute a user | `POST /api/users/{id}/mute` (confirm if server-backed) |

If the endpoints don't exist, this is **blocked on backend** — escalate
immediately, as it is the true critical-path blocker.

iOS work (after backend is confirmed):
- [ ] `Menu` overflow on every message row in `FeedView`, `MessageThreadView`, public views → "Report…" action → `ReportSheet` (reason picker + optional detail) → POST → toast
- [ ] "Report @user" on `UserProfileView`
- [ ] "Block @user" on message overflow and `UserProfileView`; optimistic local filter on feed
- [ ] `BlockedUsersView` reachable from `SettingsView`; unblock action
- [ ] Mute (local-only if no server endpoint)
- [ ] Terms/community-guidelines acceptance checkbox on `RegisterView` (blocks submit until checked); link to a live URL (confirm below in §2)
- [ ] Surface Terms + Guidelines links in `SettingsView` → About
- [ ] New files: `Views/ReportSheet.swift`, `Views/BlockedUsersView.swift`, `Models/Moderation.swift`
- [ ] New `APIClient` methods: `reportMessage`, `reportUser`, `blockUser`, `unblockUser`, `blockedUsers` (and mute variants if supported)
- [ ] Unit tests (MockURLSession) for all new API methods; decoding tests for new models
- [ ] `#Preview` for all new views; `.accessibilityLabel` on all new controls

#### Phase 0.5 — Info.plist Hygiene  `Tiny` ⛔
One-file PR; do this in parallel with Phase 14.

- [ ] Add to `InterlinedList/Info.plist`:
  ```xml
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  ```
- [ ] Replace the stale `armv7` entry in `UIRequiredDeviceCapabilities` with `arm64`:
  ```xml
  <key>UIRequiredDeviceCapabilities</key>
  <array>
      <string>arm64</string>
  </array>
  ```
- [ ] Confirm `AppIcon` asset catalog has no empty wells and no alpha channel on the 1024×1024 PNG

---

### Tier 1 — v1 parity (land before or alongside the first submission)

#### Phase 9 — Push Notifications (APNs)  `Medium` ⭑
- [ ] Add **Push Notifications** capability + `aps-environment` entitlement in Xcode (Target → Signing & Capabilities → "+ Capability")
- [ ] Enable **Push Notifications** on the App ID in the developer portal (§ below)
- [ ] Create APNs Auth Key (.p8) in portal → Keys → hand Key ID + Team ID + `.p8` to backend owner
- [ ] New `Services/PushService.swift` — request permission after login; POST device token to `POST /api/push/register`; DELETE on logout via `DELETE /api/push/unregister`
- [ ] Route push notification taps through the existing `interlinedlist://` deep-link handler
- [ ] Handle foreground presentation and badge clearing on app open
- [ ] Wire lifecycle hooks via `UIApplicationDelegateAdaptor` in `InterlinedListApp.swift`
- [ ] New `APIClient` methods: `registerPushDevice`, `unregisterPushDevice`

#### Phase 10 — Document Inline Image Upload  `Small`
- [ ] In the document editor (`Views/DocumentsView.swift`), add `PhotosPicker` → `POST /api/documents/:id/images/upload` → insert `![alt](url)` at cursor
- [ ] Reuse existing `uploadImage` patterns for progress + failure handling
- [ ] New `APIClient` method: `uploadDocumentImage(documentId:data:mimeType:)`
- [ ] Unit test (MockURLSession, multipart shape)

#### Phase 15 — Post on Behalf of an Organization  `Small`
- [ ] Confirm the create-message endpoint accepts an org-author field (likely `organizationId` in camelCase body); if not, document in `GAP-ENDPOINTS.md` and defer
- [ ] "Post as" picker in `ComposeView` (self vs. orgs where user is owner/admin)
- [ ] Thread org ID through `postMessage(...)` and `CreateMessageBody`

---

### Deferred — post-v1

| # | Phase | Effort | Blocker |
|---|---|---|---|
| 16 | Document offline delta sync | Large | none (feature-flagged) |
| 17 | Realtime updates (WebSocket/SSE) | Large | backend realtime endpoint |
| 11 | GitHub integration | Medium | backend Bearer auth for `/api/github/*` |
| 13b | Tag discovery | Small | `GET /api/tags/trending` endpoint |
| 18 | LinkedIn org cross-post targets | Small | undocumented `linkedInTargets` contract |

---

## 2. Keys, Tokens & Credentials

Gather these **before** archiving. None are committed to the repo.

| Artifact | Where to obtain | Who holds it | One-time? |
|---|---|---|---|
| **Apple Developer Program membership** | developer.apple.com/programs/ | Account owner | Annual renewal ($99/yr) |
| **APNs Auth Key (.p8)** | Portal → Certificates, IDs & Profiles → Keys → "+ " → enable APNs | Backend owner | Yes — download once, non-recoverable |
| **App Store Connect API key (.p8)** | ASC → Users and Access → Integrations → Keys | CI / upload scripts | Yes — optional, for scripted upload only |
| **Demo reviewer account** | Register at interlinedlist.com with email/password | Kept in a password manager; pasted into ASC review notes | Refresh as needed |
| **Privacy Policy URL** | Must be live at `https://interlinedlist.com/privacy` | Backend/marketing | Verify with `curl -sI` |
| **Support URL** | e.g. `https://interlinedlist.com/help`; confirm it resolves | Backend/marketing | Verify with `curl -sI` |
| **Community Guidelines / EULA URL** | e.g. `https://interlinedlist.com/terms` or `/guidelines`; must be a published, publicly accessible page | Backend/legal | Required for Phase 14 terms gate (Apple 1.2) |

**APNs key details to record (after creation — do not lose these):**

```
APNs Key ID:   _____________
Team ID:       BJA9558E4B
.p8 location:  (secure vault — NOT the repo)
```

---

## 3. Costs

| Item | Cost | Notes |
|---|---|---|
| **Apple Developer Program** | $99 USD/year | Mandatory to upload and distribute; renews annually |
| **App Store distribution** | $0 | Free app; Apple takes 0% on free downloads |
| **TestFlight** | Included | Part of Developer Program |
| **Screenshots** | $0 | Captured from the iOS Simulator via `xcrun simctl` |
| **Third-party SDKs / services** | $0 | Pure Apple frameworks; no licensing fees |
| **CI (GitHub Actions)** | $0 (current volume) | Existing workflow builds only; no paid minutes needed at current PR cadence |
| **App Store Connect API key** | $0 | Included in Developer Program |

**Total recurring cost: $99/year.**

> If you later add crash analytics, remote config, or A/B testing via a
> third-party SDK, add those costs here.

---

## 4. Required Assets

### App icon
- Already present: `InterlinedList/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Must be 1024×1024 px, flat PNG, **no alpha/transparency**, **no rounded corners** (Apple rounds it)
- Open the asset catalog in Xcode and confirm there are no yellow warnings or empty wells

### Screenshots (required — iPhone only)
Apple requires at least one of the two mandatory sizes:

| Size | Simulator | Resolution |
|---|---|---|
| **6.9"** (required) | iPhone 16 Pro Max | 1320 × 2868 px |
| **6.5"** (required) | iPhone 15 Plus or 14 Plus | 1242 × 2688 px |

Apple scales down to smaller devices from these two, so you don't need
additional sizes unless you want pixel-perfect control on smaller screens.

Capture workflow:
```bash
# Boot the target simulator, launch the app, navigate to the desired screen, then:
xcrun simctl io booted screenshot ~/Desktop/feed-6-9.png
```

Minimum screens to capture (in order of user-facing importance):
1. Feed (home timeline)
2. Compose / new post
3. Lists view
4. Profile view
5. Settings

### Store listing copy

| Field | Limit | Notes |
|---|---|---|
| **App name** | 30 chars | "InterlinedList" — verify uniqueness in ASC at record creation |
| **Subtitle** | 30 chars | e.g. "Social lists, shared" |
| **Description** | 4,000 chars | Written for the App Store listing; pitch the core value prop |
| **Keywords** | 100 chars total | Comma-separated; drives search; no spaces after commas |
| **Promotional text** | 170 chars | Shown above description; changeable without a new submission |
| **What's New** | 4,000 chars | For v1: "Initial release." |

### Age rating questionnaire
Fill honestly in ASC after Phase 14 lands. A UGC social app with content
reporting and blocking in place typically rates **17+** (infrequent/mild
mature or suggestive themes; UGC). Answering before Phase 14 ships risks
inconsistency if reviewers probe the blocking features.

### App Privacy "nutrition label"
Declare every data type the app sends. Based on the current API surface:

| Data type | ASC category | Purpose |
|---|---|---|
| Email address | Contact Info | Account management |
| Display name, bio | User Content | App functionality |
| Posts, lists, documents | User Content | App functionality |
| Avatar image | User Content | App functionality |
| User identifier | Identifiers | App functionality |
| Linked OAuth identities (provider + handle) | Identifiers | Account management |
| Device push token (Phase 9) | Device ID | App functionality (notifications) |

The app does **no tracking, no ads, no analytics SDK**. Mark "Data Not Used
to Track You" and "Data Not Linked to You" for the device push token (it's
ephemeral and server-managed). Email and user content are linked to the
account and used only for App Functionality / Account Management.

---

## 5. Xcode Project Prep (one-time, before first archive)

### 5.1 Register the App ID
1. Developer portal → Certificates, IDs & Profiles → Identifiers → "+"
2. App IDs → App. Bundle ID (Explicit): `com.interlinedlist.app`
3. Enable capability: **Push Notifications**
4. Save

### 5.2 Signing
- Target → Signing & Capabilities → **Automatically manage signing**, Team = `BJA9558E4B`
- Xcode creates the Apple Distribution certificate and App Store provisioning profile on first archive

### 5.3 Capabilities to add
- **Push Notifications** — required (Phase 9 ships in v1); adds `aps-environment` entitlement
- No other capabilities are needed; unused entitlements can trigger provisioning failures

### 5.4 Build number
- Keep **Version** `1.0` for the first release
- Increment **Build** (`CURRENT_PROJECT_VERSION`) for every upload, including re-uploads after rejection:
  ```bash
  agvtool next-version -all   # or edit CURRENT_PROJECT_VERSION in Build Settings
  ```

---

## 6. App Store Connect Setup (one-time)

1. appstoreconnect.apple.com → Apps → "+" → New App
   - Platform: iOS
   - Name: **InterlinedList**
   - Primary language: English (U.S.)
   - Bundle ID: `com.interlinedlist.app`
   - SKU: `interlinedlist-ios` (internal only)
   - User access: Full
2. **Pricing and Availability** → Free; choose territories (all recommended for v1)
3. **App Information**:
   - Primary category: **Social Networking**; secondary category: TBD (Productivity is a common pairing)
   - Privacy Policy URL: `https://interlinedlist.com/privacy`
   - Support URL: `https://interlinedlist.com/help` (confirm)
   - Age rating: fill the questionnaire (§4 above)

---

## 7. Archive & Upload

### GUI path (recommended for first submission)
1. Xcode destination: **Any iOS Device (arm64)** (not a simulator)
2. Scheme build config: Product → Scheme → Edit Scheme → Archive → Build Configuration = **Release**
3. Product → **Archive** → wait for build
4. Organizer → select archive → **Distribute App** → App Store Connect → **Upload** → automatic signing → Upload
5. Build appears in ASC / TestFlight after processing (5–30 min)

### CLI path (for CI or repeatability)
```bash
# Archive
xcodebuild -scheme InterlinedList \
  -destination 'generic/platform=iOS' \
  -archivePath build/InterlinedList.xcarchive \
  archive

# Export & upload
xcodebuild -exportArchive \
  -archivePath build/InterlinedList.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

`ExportOptions.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>            <string>app-store-connect</string>
    <key>teamID</key>            <string>BJA9558E4B</string>
    <key>signingStyle</key>      <string>automatic</string>
    <key>destination</key>       <string>upload</string>
    <key>uploadSymbols</key>     <true/>
</dict>
</plist>
```

Alternatively, drag the exported `.ipa` into **Transporter** (free on the Mac App Store).

---

## 8. TestFlight → Submit

### TestFlight
1. After processing, the build appears under TestFlight in ASC
2. Add **Test Information**: beta description, feedback email, demo account instructions
3. **Internal testing** (up to 100 team members) — no beta review, installs instantly
4. **External testing** — requires a short Beta App Review

Smoke-test checklist on a real device before submitting for App Store review:
- [ ] Email/password login and registration
- [ ] OAuth (at least one provider — Mastodon or Bluesky)
- [ ] Compose + post (text, image)
- [ ] Feed scroll, dig/undig, reply
- [ ] Lists and Documents CRUD
- [ ] Deep-link callbacks (`interlinedlist://reset-password`, `interlinedlist://verify-email`)
- [ ] Push notification receipt and tap routing (Phase 9)
- [ ] Settings, sign-out, delete-account flow
- [ ] Report/block flows (Phase 14)

### Submit for App Store review
1. ASC → app → version → **Prepare for Submission**
2. Attach the TestFlight build
3. Confirm screenshots, description, keywords, URLs, age rating, App Privacy label
4. **Review notes** (critical — write these carefully):
   - Provide the demo login (email + password for a production account)
   - State: *"Subscriptions are managed exclusively at interlinedlist.com. There is no in-app purchase, paywall, or billing UI in this app."*
   - Point to the in-app account deletion path: *Profile → Edit Profile → Delete Account (double-confirm)*
   - Point to the report/block entry points: *"To report content: tap the ... menu on any post → Report. To block a user: tap the ... menu on any post or visit their profile → Block."*
5. Export compliance: handled by `ITSAppUsesNonExemptEncryption=false` (Phase 0.5); no prompt
6. **Submit for Review**

---

## 9. Post-Submission

- Review typically completes in **24–48 hours** for a new app (can be longer)
- Monitor status: ASC → Activity, or enable email notifications
- **If rejected:** respond in Resolution Center, fix the issue, increment the build number, re-archive, re-upload, resubmit
- **On approval:** choose **manual release** to control launch timing; switch to automatic after the first version

---

## 10. Common Rejection Triggers — Preempt Them

| Risk | Mitigation |
|---|---|
| **UGC safety (Guideline 1.2)** — no report/block/EULA on a social app | Phase 14 is a hard gate; do not submit before it ships |
| **Anti-steering (3.1.1 / 3.1.3)** — any hint of external subscription/purchase | The build is silent on billing by design; do not add any "subscribe" or "upgrade" text or link |
| **Broken demo login** | Register a stable production account; keep it active; confirm before submitting |
| **Privacy label mismatch** | The declared data types must exactly match what the app sends; audit `APIClient` request bodies |
| **Stale device capability** | Phase 0.5 replaces `armv7` with `arm64` |
| **Icon alpha** | Phase 0.5 verifies the asset catalog; Apple rejects icons with transparency |
| **Missing privacy policy URL** | Must be live and return 200 before submission |
| **Sign in with Apple (4.8)** | The app offers email/password (first-party login) so SIWA is not required; if a reviewer pushes back, the email path is the mitigation |

---

## 11. Pre-flight Checklist

Copy this and tick it off just before submitting.

**Feature gates**
- [ ] Phase 14 — UGC safety shipped (report, block, mute, terms gate)
- [ ] Phase 0.5 — Info.plist hygiene done (`ITSAppUsesNonExemptEncryption`, `arm64`, icon)
- [ ] Phase 9 — Push notifications wired (APNs capability, PushService, register/unregister)

**Accounts & credentials**
- [ ] Apple Developer Program membership active; agreements accepted in ASC
- [ ] Your role on team `BJA9558E4B` is Admin or App Manager
- [ ] APNs Auth Key (.p8) created, Key ID recorded, handed to backend owner
- [ ] Demo reviewer account registered and confirmed working on production
- [ ] Privacy Policy URL live: `https://interlinedlist.com/privacy`
- [ ] Support URL live (e.g. `https://interlinedlist.com/help`)
- [ ] Community Guidelines / EULA URL live and linked from `RegisterView`

**Xcode project**
- [ ] App ID `com.interlinedlist.app` registered in portal with Push enabled
- [ ] Push Notifications capability + `aps-environment` entitlement added in Xcode
- [ ] No other unused capabilities/entitlements
- [ ] Automatic signing, team `BJA9558E4B`, archive signs cleanly
- [ ] Build number incremented from any prior upload

**App Store Connect record**
- [ ] App record created (name, bundle ID, SKU, Full access)
- [ ] Free pricing, territories selected
- [ ] Category, Privacy Policy URL, Support URL filled
- [ ] Age rating questionnaire completed (after Phase 14 ships)

**Assets**
- [ ] App icon: no empty wells, no alpha (verified in Xcode asset catalog)
- [ ] Screenshots: 6.9" and 6.5" sets uploaded in ASC
- [ ] Description, subtitle, keywords, promotional text written and entered
- [ ] App Privacy nutrition label completed and saved in ASC

**Upload & review**
- [ ] Build archived (Release, Any iOS Device)
- [ ] Build uploaded and processed (visible in TestFlight)
- [ ] TestFlight smoke-test passed on a real device
- [ ] Review notes written: demo creds, web-only billing note, delete-account path, report/block path
- [ ] Submit for Review
