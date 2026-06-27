# GAP-APPLE — Shipping InterlinedList to the App Store

A step-by-step checklist to sign, prepare, and submit the iOS app to the
Apple App Store. Written against the current project state and tailored to
this app's specifics (free app, web-only subscriptions, OAuth + email
auth, in-app account deletion).

Legend for each step:
- 🖥️ **Xcode** — must be done in the Xcode GUI.
- 🌐 **Web** — App Store Connect / Developer portal (browser).
- ⌨️ **CLI** — can be scripted from the terminal.
- 📝 **File** — an edit to a file in this repo.

---

## 0. Where the project stands today

| Setting | Current value | Notes |
|---|---|---|
| Bundle identifier | `com.interlinedlist.app` | tests target: `com.interlinedlist.app.tests` |
| Marketing version | `1.0` (`MARKETING_VERSION`) | the public "version" |
| Build | `1` (`CURRENT_PROJECT_VERSION`) | must increment every upload |
| Deployment target | iOS 17.0 | |
| Device family | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) | iPad not a target → iPhone screenshots only |
| Signing | Automatic, `DEVELOPMENT_TEAM = BJA9558E4B` | team already set |
| App icon | `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | single-size 1024 icon present ✅ |
| URL scheme | `interlinedlist://` registered | used for OAuth / verify / reset deep links |
| Third-party deps | none | pure Apple frameworks |

Two Info.plist items to fix **before** the first upload — see §3.5.

**Scope decisions baked into this doc (2026-06-27):** the first release
targets **full web parity** and **includes push notifications (Phase 9)**,
so the Push capability/entitlement and an APNs key are now part of the
first ship (§2.3, §3.6, §0.1). The app also still needs the **UGC
safety/moderation** work (report/block/terms gate) before it can pass
review — that's tracked as **Phase 14** in `GAP-NEXT-STEPS.md` and called
out in §5.4 / §11 below.

---

## 0.1 Open questions & info to gather before submission

These are the unknowns that block a clean submission. Each line says **how
to obtain it**. Resolve them before §7 (archive/upload); none require code.

**Account & identity**
- [ ] **Membership active + your role.** Confirm the Apple Developer
      Program membership is paid/active and you are **Admin** or **App
      Manager** on team `BJA9558E4B`.
      *How:* <https://developer.apple.com/account> ▸ Membership details;
      Users and Access shows your role.
- [ ] **Team ID is correct.** This doc assumes `BJA9558E4B`.
      *How:* `xcodebuild -showBuildSettings -scheme InterlinedList | grep DEVELOPMENT_TEAM`,
      or the portal Membership page. Update every occurrence if it differs.
- [ ] **App name is available.** "InterlinedList" must be globally unique on
      the App Store.
      *How:* App Store Connect ▸ Apps ▸ "+" ▸ New App — if the name is
      taken you'll be told at reservation; have a fallback name ready.

**Listing metadata (owner decisions needed)**
- [ ] **Primary / secondary category.** Likely **Social Networking**;
      confirm the pair.
- [ ] **Age rating answers.** A UGC social app typically lands 17+. Answer
      the questionnaire honestly **after Phase 14 lands** (the answers
      depend on having reporting/blocking in place).
- [ ] **Demo reviewer account.** A stable **production** email/password
      login for App Review (OAuth is awkward for reviewers).
      *How:* register one on `interlinedlist.com`; keep it active; put the
      creds in the review notes (§9) — **never commit them to the repo**.

**URLs to verify live (200 OK)**
- [ ] **Privacy policy:** `https://interlinedlist.com/privacy` (mandatory).
- [ ] **Support URL:** confirm the real one (`/help`?) resolves.
- [ ] **Community Guidelines / EULA** for the Phase 14 terms gate: confirm a
      published zero-tolerance guidelines page exists (e.g. `/terms`,
      `/guidelines`, `/community`). If none exists, the app can present
      **Apple's standard EULA** instead — decide which.
      *How:* `curl -sI <url>` or open in a browser; coordinate with
      `GAP-ENDPOINTS.md` §H.

**App Privacy "nutrition label" inputs**
- [ ] **Enumerate collected data → purpose.** From the API request bodies
      the app sends: email, display name/bio, user content (posts, lists,
      documents), avatar image, user identifier, linked-OAuth identities,
      and — with Phase 9 — the **device push token**. Map each to a purpose
      (App Functionality / Account Management; the app does no tracking/ads).
      *How:* skim `APIClient` request bodies; fill App Store Connect ▸ App
      Privacy. Must match what the app actually sends (§11).

**Push (Phase 9 — now in v1)**
- [ ] **APNs Auth Key (.p8).** The backend needs it to send pushes.
      *How:* portal ▸ Certificates, IDs & Profiles ▸ **Keys** ▸ "+" ▸ enable
      **Apple Push Notifications service (APNs)** ▸ download the `.p8`
      **once** (non-recoverable). Hand the **Key ID + Team ID + .p8** to
      the backend owner; enable **Push Notifications** on the App ID (§2.3).
- [ ] **APNs environment.** Confirm whether the backend sends via sandbox
      (TestFlight/dev) vs production and that it keys off the right
      `aps-environment`.

**Upload tooling (optional, for CLI/CI)**
- [ ] **App Store Connect API key (.p8).** For scripted upload (§7.2).
      *How:* App Store Connect ▸ Users and Access ▸ Integrations ▸ Keys ▸
      generate; note Issuer ID + Key ID; store the `.p8` securely.

**Assets**
- [ ] **Screenshots** at 6.9" and 6.5" (§6).
      *How:* boot the iPhone 16 Pro Max + a 6.5" simulator, then
      `xcrun simctl io booted screenshot shot.png` per screen.

---

## 1. Prerequisites (one-time)

1. 🌐 **Apple Developer Program membership** — $99/year, at
   <https://developer.apple.com/programs/>. Required to upload and
   distribute. Confirm the membership is active and you're an **Admin** or
   **App Manager** on the team `BJA9558E4B` (Account → Membership).
2. 🖥️ **Xcode** — install the latest from the Mac App Store. Sign in:
   Xcode ▸ Settings ▸ Accounts ▸ "+" ▸ Apple ID. Confirm the team appears.
3. ⌨️ Confirm command-line tools point at that Xcode:
   `sudo xcode-select -s /Applications/Xcode.app` then `xcodebuild -version`.
4. 🌐 **Agreements** — App Store Connect ▸ Business: accept the current
   "Paid Apps" and "Free Apps" agreements. Uploads silently fail if the
   active agreement isn't accepted.

---

## 2. Register the App ID & bundle identifier (one-time)

With automatic signing, Xcode can create the App ID for you on first
archive, but doing it explicitly avoids surprises:

1. 🌐 Developer portal ▸ Certificates, IDs & Profiles ▸ **Identifiers** ▸ "+".
2. Select **App IDs ▸ App**. Description: "InterlinedList". Bundle ID:
   **Explicit** = `com.interlinedlist.app`.
3. **Capabilities**: enable **Push Notifications** here — Phase 9 (push) is
   in v1, so the App ID needs the push capability (and the matching Xcode
   entitlement, §3.6). Leave everything else off; nothing else is needed
   for the v1 feature set.
4. Save.

   > **§2.3 APNs key.** Push also needs an **APNs Auth Key (.p8)** for the
   > backend to send notifications — create it under Keys and hand the
   > Key ID + Team ID + `.p8` to the backend owner (§0.1).

> You do **not** need an Associated Domains entry for the current OAuth /
> deep-link flow — it uses the custom `interlinedlist://` URL scheme, which
> requires no portal config. Only add Associated Domains if you later move
> to Universal Links (`https://interlinedlist.com/...`).

---

## 3. Xcode project prep

### 3.1 Signing 🖥️
1. Open `InterlinedList.xcodeproj`, select the **InterlinedList** target ▸
   **Signing & Capabilities**.
2. Check **Automatically manage signing**. Team = your team
   (`BJA9558E4B`). Xcode will create the **Apple Distribution** certificate
   and **App Store** provisioning profile on first archive.
3. If you prefer manual signing later, you'd create an *Apple Distribution*
   certificate and an *App Store* provisioning profile in the portal and
   select them here — not needed for the first ship.

### 3.2 Version & build 🖥️/📝
- Keep **Version** `1.0` for the first release. **Build** must be unique &
  monotonically increasing for *every* upload (even rejected ones). Bump
  `CURRENT_PROJECT_VERSION` to `1` now, then `2`, `3`… on each re-upload.
- ⌨️ Quick bump from CLI: `agvtool next-version -all` (or edit
  `CURRENT_PROJECT_VERSION` in build settings).

### 3.3 App icon 🖥️
- A 1024×1024 icon is present. Open `Assets.xcassets ▸ AppIcon` and confirm
  there are **no empty wells / warnings** (a single 1024 "Any Appearance"
  slot is fine for iOS 17). The icon must be a flat PNG with **no alpha /
  transparency** and no rounded corners (Apple rounds it). If the asset
  catalog shows a yellow warning, fill the required slot.

### 3.4 Launch screen 🖥️
- The project uses a generated launch screen (`UILaunchScreen` empty dict /
  `INFOPLIST_KEY_UILaunchScreen_Generation = YES`). That's valid. Launch
  the app once on a device to confirm it isn't a black flash; add a
  branded launch storyboard later if desired (not required to ship).

### 3.5 Info.plist fixes 📝 (do these before first upload)

`InterlinedList/Info.plist`:

1. **Encryption export compliance.** Add:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
   The app only uses standard HTTPS/TLS (exempt). Without this key, every
   upload stops to ask the export-compliance question in App Store Connect.
   Set `false` to skip it.

2. **Remove the stale `armv7` capability.** `UIRequiredDeviceCapabilities`
   currently lists `armv7` (32-bit) — iOS 17 is **arm64-only**, and this
   entry is wrong and can cause "app not compatible" oddities. Change it to:
   ```xml
   <key>UIRequiredDeviceCapabilities</key>
   <array>
       <string>arm64</string>
   </array>
   ```
   (Keep `network` only if you truly require it; `arm64` is the safe set.)

3. **Privacy usage strings** — none are required today: the app uses
   `PhotosPicker` (PHPicker), which reads photos out-of-process and needs
   **no** `NSPhotoLibraryUsageDescription`. There is no camera, mic,
   location, or contacts access. If you ever add direct photo-library or
   camera access, add the matching `NS*UsageDescription` or the app is
   rejected.

### 3.6 Capabilities currently needed 🖥️
- **Push Notifications** — required for v1 because Phase 9 (APNs) ships in
  the first release. Target ▸ Signing & Capabilities ▸ "+ Capability" ▸
  **Push Notifications**; Xcode adds the `aps-environment` entitlement and
  Push to the provisioning profile. Pair with enabling Push on the App ID
  (§2.3) and creating the APNs key (§0.1).
- Do **not** add any *other* entitlement you don't use — unused
  entitlements (associated domains, iCloud, etc.) can trigger provisioning
  failures or review questions.

---

## 4. App Store Connect — create the app record 🌐

1. <https://appstoreconnect.apple.com> ▸ **Apps** ▸ "+" ▸ **New App**.
   - Platform: iOS. Name: **InterlinedList** (must be globally unique on
     the store). Primary language: English (U.S.).
   - Bundle ID: select `com.interlinedlist.app`.
   - SKU: any internal string, e.g. `interlinedlist-ios`.
   - User access: Full.
2. **Pricing and Availability** ▸ Price = **Free**. Choose territories.
3. Fill the **App Information**:
   - Category (primary/secondary), content rights, age rating
     questionnaire (see §5.4).
   - **Privacy Policy URL** (required): `https://interlinedlist.com/privacy`.
   - Support URL: `https://interlinedlist.com/help` (or similar).

---

## 5. Compliance specifics for *this* app

### 5.1 In-app purchase / anti-steering (Guideline 3.1.1 & 3.1.3) ✅ by design
- The app sells **nothing** in-app and shows **no** subscription/paywall
  UI; subscription management is entirely on the web. This is the safe
  path. **Do not** add a "Subscribe", "Upgrade", price text, or any link
  that points users to the website to pay — that violates anti-steering and
  is the most common rejection for apps with a web subscription. The
  current build is compliant *because* it stays silent on billing; keep it
  that way.

### 5.2 Account deletion (Guideline 5.1.1(v)) ✅ already implemented
- Apple requires any app with account creation to offer **in-app account
  deletion**. The app has it (Profile ▸ Edit ▸ delete account → double
  confirm → forced logout). When asked in review notes, point to that path.

### 5.3 Login services (Guideline 4.8) — likely fine, verify
- 4.8 applies when an app uses third-party login (you offer GitHub,
  Mastodon, Bluesky, LinkedIn, X via OAuth). Because the app **also** offers
  plain email/password sign-up (a first-party login that doesn't share data
  with a third party), you generally do **not** need to add *Sign in with
  Apple*. If a reviewer pushes back, the email/password option is the
  mitigation; otherwise be prepared to add Sign in with Apple.

### 5.4 Age rating 🌐
- Complete the questionnaire honestly. A social app with user-generated
  content typically lands 12+/17+. **UGC apps must also** provide: a way to
  report objectionable content, block users, and a posted EULA/agreement —
  Apple checks for these on social apps (Guideline 1.2). **The app does not
  have these yet** — they are tracked as **Phase 14 (UGC safety &
  moderation)** in `GAP-NEXT-STEPS.md` and **must ship before this app can
  pass review.** Treat Phase 14 as a hard gate on submission.

### 5.5 Export compliance ✅ handled by §3.5.1
- With `ITSAppUsesNonExemptEncryption=false`, no annual self-classification
  report is needed.

---

## 6. App Store metadata & screenshots 🌐

Required before you can submit a build:
- **Screenshots** — iPhone only (the app is iPhone-only). Provide for the
  current required sizes: **6.9"** (iPhone 16 Pro Max, 1320×2868) and
  **6.5"** (1242×2688). Apple scales down for smaller devices, so those two
  sets usually suffice. Capture via the iPhone 16 Pro Max simulator
  (⌨️ `xcrun simctl io booted screenshot shot.png`) or a device.
- **Description, keywords, promotional text, what's new.**
- **App preview** video — optional.
- Marketing app icon is taken from the build's 1024 icon.

---

## 7. Archive & upload the build

### 7.1 Xcode GUI path 🖥️ (recommended for the first ship)
1. Select the run destination **Any iOS Device (arm64)** (not a simulator —
   archiving requires a device/generic destination).
2. Ensure the scheme builds **Release**: Product ▸ Scheme ▸ Edit Scheme ▸
   Archive ▸ Build Configuration = **Release**.
3. **Product ▸ Archive**. Wait for the build.
4. The **Organizer** opens ▸ select the archive ▸ **Distribute App** ▸
   **App Store Connect** ▸ **Upload** ▸ accept the automatic signing ▸
   Upload. (Choose "Upload" not "Export".)
5. The build appears in App Store Connect under the app's **TestFlight** /
   **Build** sections after processing (5–30 min).

### 7.2 CLI path ⌨️ (for CI / repeatability)
```bash
# 1. Archive (Release)
xcodebuild -scheme InterlinedList \
  -destination 'generic/platform=iOS' \
  -archivePath build/InterlinedList.xcarchive \
  archive

# 2. Export & upload using an ExportOptions.plist (below)
xcodebuild -exportArchive \
  -archivePath build/InterlinedList.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```
`ExportOptions.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
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
- Auth for upload: create an **App Store Connect API key** (App Store
  Connect ▸ Users and Access ▸ Integrations ▸ Keys), download the `.p8`,
  and either let Xcode store it or use `xcrun altool`/`notarytool`-style
  env. Alternatively upload the exported `.ipa` with **Transporter** (Mac
  App Store app) — drag the `.ipa` in and Deliver.

---

## 8. TestFlight (strongly recommended before public release) 🌐
1. After processing, the build shows under **TestFlight**.
2. Provide **Test Information** (beta description, feedback email) and a
   demo account for reviewers — give them an **email/password test login**
   (OAuth providers are awkward for reviewers).
3. **Internal testing** (your team, up to 100, no beta review) installs
   instantly. **External testing** requires a short Beta App Review.
4. Verify on a real device: login, post + cross-post, lists/schema, follow
   flows, settings, deep-link callbacks (`interlinedlist://`).

---

## 9. Submit for App Store review 🌐
1. App Store Connect ▸ your app ▸ **(version) Prepare for Submission**.
2. Select the uploaded **Build**.
3. Confirm: screenshots, description, keywords, support/privacy URLs, age
   rating, **App Privacy** "nutrition label" (declare what you collect —
   typically: email/account data, user content, identifiers; map each to a
   use). The label is required and separately editable under **App
   Privacy**.
4. **Review notes**: include the demo login, note that *subscriptions are
   managed on the web and there is no in-app purchase*, and point to the
   in-app **account deletion** path.
5. Export compliance: with §3.5.1 set, you'll see no prompt.
6. **Add for Review ▸ Submit**.

---

## 10. After submission
- Status flows: *Waiting for Review → In Review → Pending/Approved*. First
  reviews are often 24–48h.
- On rejection, respond in **Resolution Center**; fix, bump the **build**
  number (§3.2), re-archive, re-upload, resubmit.
- On approval choose **manual** or **automatic** release. For a first
  launch, manual lets you coordinate timing.

---

## 11. Common rejection triggers for this app (pre-empt them)
- **Anti-steering**: any hint of an external subscription/purchase. Keep
  the build silent on billing (§5.1).
- **UGC safety (1.2)**: missing content reporting / user blocking / EULA on
  a social app. **Currently missing — see Phase 14 in `GAP-NEXT-STEPS.md`;
  it must ship before submission.**
- **Broken demo login**: give reviewers working email/password creds.
- **Privacy label mismatch**: the declared data must match what the app
  actually sends (email, posts, identifiers).
- **Stale device-capability / icon alpha**: fixed by §3.3 and §3.5.2.
- **Incomplete metadata**: privacy policy URL is mandatory.

---

## 12. Quick pre-flight checklist
- [ ] §0.1 open questions resolved (team ID, app-name availability, demo
      account, category, age-rating, guidelines/EULA URL, privacy inputs)
- [ ] Apple Developer membership active; agreements accepted (§1)
- [ ] App ID `com.interlinedlist.app` registered, **Push enabled** (§2)
- [ ] Automatic signing, team set, archive signs cleanly (§3.1)
- [ ] Build number incremented (§3.2)
- [ ] App icon has no warnings / no alpha (§3.3)
- [ ] `ITSAppUsesNonExemptEncryption=false` added (§3.5.1)
- [ ] `armv7` device capability replaced with `arm64` (§3.5.2)
- [ ] **Push Notifications capability + `aps-environment` entitlement** set;
      APNs `.p8` key created and handed to backend (§2.3 / §3.6 / §0.1)
- [ ] No *other* unused entitlements/capabilities (§3.6)
- [ ] App Store Connect record + Free pricing + privacy/support URLs (§4)
- [ ] **Phase 14 UGC safety shipped** — report/block/mute + terms gate
      (§5.4; `GAP-NEXT-STEPS.md` Phase 14) — **hard gate**
- [ ] iPhone 6.9"/6.5" screenshots + description (§6)
- [ ] Archive uploaded; build processed (§7)
- [ ] TestFlight smoke test on device + demo login (§8)
- [ ] App Privacy label completed; review notes with demo creds (§9)
