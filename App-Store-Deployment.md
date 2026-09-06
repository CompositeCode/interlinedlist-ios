# App Store Deployment — InterlinedList iOS

Single reference for getting the app from its current state to the App Store.
For feature/parity context see `the-gaps.md` (iOS↔web parity + backend asks) and
`the-gaps-access.md` (access-control audit); this document synthesises them into an
actionable submission checklist targeted at whoever is doing the work.
*(The older `GAP-APPLE.md` / `GAP-NEXT-STEPS.md` / `GAP-ENDPOINTS.md` split was
consolidated into those two docs and no longer exists.)*

> **▶ Status — 2026-09-05.** **iOS engineering for v1 is done.** Every Tier 0 and
> Tier 1 phase below has shipped, plus the whole parity backlog (`the-gaps.md`
> D1–D3, G1–G10, G12–G14) and all seven access-control gaps (`the-gaps-access.md`
> G1–G7). Working tree `dev` = `main` = origin, clean; last verification run
> **823 unit tests, 0 failures, build green** (E2E excluded).
>
> **Everything still open is submission logistics, not code:** Apple portal setup
> (App ID + Push + **Associated Domains**), APNs `.p8`, ASC record + listing copy +
> privacy label, screenshots, demo reviewer account, build-number bump, archive →
> TestFlight device smoke test → submit. Work §§2, 4, 5, 6, 7, 8 in that order; the
> tick-list lives in `App-Store-Deployment-Checklist.md`.

**App details at a glance**

| Field | Value |
|---|---|
| Bundle ID | `com.interlinedlist.app` |
| Version | `1.0` |
| Build | `1` — **not yet bumped**; increment before the first upload and every re-upload |
| Deployment target | iOS 17.0 |
| Device family | iPhone only |
| Team ID | `BJA9558E4B` |
| Signing | Automatic |
| URL scheme | `interlinedlist://` |
| Universal Links | `applinks:interlinedlist.com` — entitlement in the repo, AASA live on the backend; **portal capability not yet enabled** |
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
| 0.5 | Info.plist hygiene (`ITSAppUsesNonExemptEncryption`, `arm64`, icon) | 2026-07-05 |
| 14 | UGC safety — report message/user, block/unblock, mute, terms gate on register | 2026-07-05 |
| 9 | Push notifications — `PushService`, APNs delegate, register/unregister, tap routing | 2026-07-05 |
| — | Parity Tier 0 — D1/D2/D3 verb fixes (POST/PUT → PATCH) on profile, message edit, notification read | 2026-07-31 |
| — | G1 Direct Messages · G2 Sharing (share-links + doc collaborators) · G3 Templates · G5 LinkedIn targets · G6 People search · G7 Muted users · G8 Exports · G12 Active sessions | 2026-07-31 |
| 11 | GitHub integration — GitHub-backed lists, issue read/create/close, repo picker (G4) | 2026-07-31 |
| 16 | Offline document sync — delta pull, outbox push, conflict-copy (G9, slices 1–3) | 2026-08-02 |
| 10 | Document inline image upload (`uploadDocumentImage` + editor picker) | 2026-08-13 |
| — | Markdown editor format toolbar · email share-invites | 2026-08-13 |
| — | Access-control remediation — `the-gaps-access.md` G1–G7 (PRs #17–#23) | 2026-08-16 |
| 13b | Tag discovery — trending strip + `#` autocomplete (G13) · composer link preview (G14) · document deep links (G10) | 2026-08-15 |
| 15 | Post on behalf of an organization (`organizationId` in compose) | 2026-08-16 |
| — | Multi-image compose · unified sharing screen · inbound shared-list viewer · GitHub issue-close refresh | 2026-09-02 |

**What works today:** auth (email + OAuth ×5, identity linking), feed (infinite
scroll, dig, reply, search, link previews, trending tags), compose (text, multi-image,
video, cross-post incl. LinkedIn targets, repost, scheduled, post-as-org, live link
preview), lists (CRUD, parent/child nesting, schema editor, watchers, GitHub-backed
lists), documents (CRUD, folders, search, inline images, templates, collaborators,
public reader, offline delta sync with conflict copies), sharing (share-links, email
invites, inbound shared list/document viewers), direct messages, public browse,
notifications (tray, preferences, push), profile, follow, people search, moderation
(report/block/mute), organizations, active sessions, settings, exports, deep links.

**Not built — and deliberately so:** live document presence/collaborative cursors
(`the-gaps.md` G11, optional); multi-account switching and a general realtime channel
(backend-blocked, X1/X3); billing/dashboard/admin surfaces (web-only by design).

**Shipped since last update (2026-07-05):** Phase 0.5 (Info.plist: arm64, ITSAppUsesNonExemptEncryption), Phase 14 (UGC safety: report message/user, block/unblock user, mute, terms acceptance on register, blocked users in settings), Phase 9 (push notifications: PushService, APNs delegate, register/unregister device token).

**Shipped 2026-07-07 (backend sync + iOS follow-up):**
- `GET /api/user/organizations` now accepts Bearer tokens → `OrganizationListView` unblocked; no iOS workaround needed.
- `GET /api/lists/{id}/watchers/me` now returns `role` field → `WatchingResponse` model updated; `isWatchingList` returns full response.
- Self-watch via `POST /api/lists/{id}/watchers` no longer requires `userId` in body → `watchSelf(listId:)` added; `PublicListDetailView` uses it.
- Avatar update flow no longer issues trailing `GET /api/user`; uses `PATCH /api/user/update` response instead.
- Moderation unit tests expanded (bearer token + error handling tests for all 8 methods); `ModerationModelTests` added with Codable decode coverage for `BlockedUser`, `MutedUser`, and their response wrappers.

---

## 1. Feature Completion — What Must Ship Before Submission

### Tier 0 — Hard ship-blockers (nothing uploads without these) — ✅ ALL SHIPPED

#### Phase 14 — UGC Safety & Moderation  `Large` — ✅ SHIPPED 2026-07-05
Apple Guideline 1.2 requires every UGC/social app to provide: (1) report
objectionable content, (2) block abusive users, (3) a posted community-
guidelines/zero-tolerance EULA accepted at registration, and (4) a developer
contact (the support URL covers this). **The app has none of 1–3 today.**

**Backend discovery (done):** every endpoint below exists and accepts Bearer;
all eight `APIClient` moderation methods are wired and unit-tested.

| Need | Candidate endpoint |
|---|---|
| Report a message | `POST /api/messages/{id}/report` or `POST /api/report` |
| Report a user | `POST /api/users/{id}/report` |
| Block a user | `POST /api/users/{id}/block` |
| Unblock a user | `DELETE /api/users/{id}/block` |
| List blocked users | `GET /api/blocks` or `GET /api/user/blocks` |
| Mute a user | `POST /api/users/{id}/mute` (confirm if server-backed) |

iOS work — all complete:
- [x] `Menu` overflow on every message row in `FeedView`, `MessageThreadView` → "Report…" action → `ReportSheet` (reason picker + optional detail) → POST → toast
- [x] "Report @user" on `UserProfileView`
- [x] "Block @user" on message overflow and `UserProfileView`; optimistic local filter on feed
- [x] `BlockedUsersView` reachable from `SettingsView`; unblock action
- [x] Mute (server-backed via `/api/users/{id}/mute` — APIClient methods added)
- [x] Terms/community-guidelines acceptance checkbox on `RegisterView` (blocks submit until checked); links to `/terms`
- [x] Surface Terms + Community Guidelines links in `SettingsView` → About
- [x] New files: `Views/ReportSheet.swift`, `Views/BlockedUsersView.swift`, `Models/Moderation.swift`, `Services/PushService.swift`
- [x] New `APIClient` methods: `reportMessage`, `reportUser`, `blockUser`, `unblockUser`, `blockedUsers`, `muteUser`, `unmuteUser`, `mutedUsers`
- [x] Unit tests (MockURLSession) for all new API methods; decoding tests for new models
- [x] `#Preview` for all new views; `.accessibilityLabel` on all new controls

#### Phase 0.5 — Info.plist Hygiene  `Tiny` — ✅ SHIPPED 2026-07-05

- [x] Add to `InterlinedList/Info.plist`:
  ```xml
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  ```
- [x] Replace the stale `armv7` entry in `UIRequiredDeviceCapabilities` with `arm64`:
  ```xml
  <key>UIRequiredDeviceCapabilities</key>
  <array>
      <string>arm64</string>
  </array>
  ```
- [ ] Confirm `AppIcon` asset catalog has no empty wells and no alpha channel on the 1024×1024 PNG — **still to verify in Xcode before archiving**

---

### Tier 1 — v1 parity (land before or alongside the first submission) — ✅ ALL SHIPPED (code); portal/key steps remain

#### Phase 9 — Push Notifications (APNs)  `Medium` — ◑ iOS side shipped 2026-07-05; **two portal steps still open**
- [x] Add **Push Notifications** capability + `aps-environment` entitlement in Xcode (`InterlinedList.entitlements` carries `aps-environment: development`; Xcode auto-signing upgrades it to `production` on an App Store archive)
- [ ] **OPEN —** Enable **Push Notifications** on the App ID in the developer portal (§5.1)
- [ ] **OPEN —** Create APNs Auth Key (.p8) in portal → Keys → hand Key ID + Team ID + `.p8` to backend owner (§2)
- [x] New `Services/PushService.swift` — request permission after login; POST device token to `POST /api/push/register`; DELETE on logout via `DELETE /api/push/unregister`
- [x] Route push notification taps through the existing `interlinedlist://` deep-link handler
- [x] Handle foreground presentation and badge clearing on app open
- [x] Wire lifecycle hooks via `UIApplicationDelegateAdaptor` in `InterlinedListApp.swift`
- [x] New `APIClient` methods: `registerPushDevice`, `unregisterPushDevice`

#### Phase 10 — Document Inline Image Upload  `Small` — ✅ SHIPPED 2026-08-13
- [x] In the document editor (`Views/DocumentsView.swift:797,893`), `PhotosPicker` → `POST /api/documents/:id/images/upload` → insert `![alt](url)` at cursor
- [x] Reuse existing `uploadImage` patterns for progress + failure handling
- [x] New `APIClient` method: `uploadDocumentImage(documentId:data:mimeType:)` (`APIClient.swift:814`)
- [x] Unit test (MockURLSession, multipart shape)

#### Phase 15 — Post on Behalf of an Organization  `Small` — ✅ SHIPPED 2026-08-16
- [x] Confirmed: the create-message endpoint accepts `organizationId` (camelCase body)
- [x] "Post as" picker in `ComposeView` (self vs. orgs where user is owner/admin — role-filtered at `ComposeView.swift:558-565`, sent at `:715`)
- [x] Thread org ID through `postMessage(...)` and `CreateMessageBody` (`APIClient.swift:332,341`)

---

### Deferred — post-v1

| # | Phase | Effort | Status |
|---|---|---|---|
| 16 | Document offline delta sync | Large | ✅ **Shipped 2026-08-02** — slices 1–3 incl. conflict copies; flag `ILOfflineDocSync` default-on |
| 17 | Realtime updates (WebSocket/SSE) | Large | ❌ **Not buildable** — no SSE/WebSocket endpoint exists (`the-gaps.md` X3). Realtime is per-feature polling (DM `/updates`, doc `/presence`) |
| 11 | GitHub integration | Medium | ✅ **Shipped 2026-07-31** — backend now accepts Bearer; issue read/create/close, repo picker, mobile OAuth linking live |
| 13b | Tag discovery | Small | ✅ **Shipped 2026-08-15** — `/api/tags/{trending,autocomplete}` shipped on the backend; trending strip + `#` autocomplete in `FeedView` |
| 18 | LinkedIn org cross-post targets | Small | ✅ **Shipped 2026-07-31** — real `{kind,pageId?,personalPageId?}` contract; multi-select picker in `ComposeView` |
| — | Live document presence (collaborative cursors) | Medium | ⏳ **Still deferred** — `the-gaps.md` G11, optional; `/api/documents/:id/presence` is ready when wanted |

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
- Present: `InterlinedList/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (+ a dark-appearance variant)
- Must be 1024×1024 px, flat PNG, **no alpha/transparency**, **no rounded corners** (Apple rounds it)
- ✅ **Fixed 2026-09-05** — the primary icon was RGBA (fully opaque, but Apple rejects the *presence* of an alpha channel with **ITMS-90717** at upload). Re-saved as RGB with pixel data unchanged; `sips -g hasAlpha` now reports `no`. The dark-appearance variant intentionally keeps its alpha
- Open the asset catalog in Xcode and confirm there are no yellow warnings or empty wells

### Screenshots (required — iPhone only)
Apple requires at least one of the two mandatory sizes:

| Size | Simulator | Resolution |
|---|---|---|
| **6.9"** (required) | iPhone 16 Pro Max | 1320 × 2868 px |
| **6.5"** (required) | iPhone 11 Pro Max / XS Max on the iOS 17.5 runtime | 1242 × 2688 px |

> **Correction (2026-09-05):** an earlier revision named *iPhone 15 Plus* for the
> 6.5" slot — that device renders **1290 × 2796** and ASC will reject it there. No
> installed modern device produces 1242 × 2688, so a 6.5" simulator was created for
> this purpose and verified: **`IL-6.5in-11ProMax`**, UDID
> `C272D802-6737-46CC-A943-87C80749FF67` (iPhone 11 Pro Max on iOS 17.5). Both
> devices were confirmed to emit exactly the required pixel dimensions.

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

**Drafted and length-checked in `App-Store-Listing-Copy.md`** (2026-09-05) — subtitle,
promotional text, description, keywords, What's New, review notes, age-rating answers,
and the privacy-label table, all within limits and free of billing language.

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
3. Enable capabilities: **Push Notifications** *and* **Associated Domains**
   (the app ships `applinks:interlinedlist.com`; the backend already serves
   `/.well-known/apple-app-site-association` — verified live 2026-08-14)
4. Save, then **regenerate the provisioning profile** so it carries both capabilities

### 5.2 Signing
- Target → Signing & Capabilities → **Automatically manage signing**, Team = `BJA9558E4B`
- Xcode creates the Apple Distribution certificate and App Store provisioning profile on first archive

### 5.3 Capabilities to add
- **Push Notifications** — required (Phase 9 ships in v1); adds `aps-environment` entitlement ✅ present in `InterlinedList.entitlements`
- **Associated Domains** — required for Universal Links; `com.apple.developer.associated-domains = applinks:interlinedlist.com` ✅ present in `InterlinedList.entitlements`, but the **portal capability is not yet enabled** — enable it (§5.1) or the archive will fail to provision
- No other capabilities are needed; unused entitlements can trigger provisioning failures

### 5.4 Build number
- Keep **Version** `1.0` for the first release
- **Current state: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` — never uploaded, so bump the build to `2`+ (or leave `1` for the very first upload only) and increment thereafter**
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
- [ ] OAuth (at least one provider — Mastodon or Bluesky); GitHub linking via the mobile OAuth branch
- [ ] Compose + post (text, multi-image); trending-tag strip and live link preview
- [ ] Feed scroll, dig/undig, reply
- [ ] Lists and Documents CRUD; document inline image upload
- [ ] Direct Messages — inbox, open a thread, send, unread badge
- [ ] Sharing — create/copy/revoke a share-link; open a shared list/document link
- [ ] Offline document sync — airplane-mode edit, reconnect, confirm it persists
- [ ] Deep-link callbacks (`interlinedlist://reset-password`, `interlinedlist://verify-email`)
- [ ] **Universal Links** — tap an `https://interlinedlist.com/...` link and confirm it opens in-app (needs the portal capability + fresh profile)
- [ ] Push notification receipt and tap routing (Phase 9)
- [ ] Settings, sign-out, delete-account flow
- [ ] Report/block flows (Phase 14)
- [ ] **Free (non-subscriber) account** — confirm premium controls are hidden, not paywalled, and nothing surfaces upsell copy *(never yet exercised live — the only test account is a subscriber)*

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

**Feature gates** — all green as of 2026-09-05
- [x] Phase 14 — UGC safety shipped (report, block, mute, terms gate)
- [x] Phase 0.5 — Info.plist hygiene done (`ITSAppUsesNonExemptEncryption`, `arm64`, icon)
- [x] Phase 9 — Push notifications wired (PushService, register/unregister, `aps-environment: development` entitlement in place; Xcode auto-signing upgrades to production on archive)
- [x] Phases 10, 11, 13b, 15, 16 + the full `the-gaps.md` parity backlog (D1–D3, G1–G10, G12–G14) shipped
- [x] `the-gaps-access.md` G1–G7 access-control remediation shipped (PRs #17–#23)
- [x] Build + full unit suite green — **823 tests, 0 failures** (2026-09-05, E2E excluded)

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
