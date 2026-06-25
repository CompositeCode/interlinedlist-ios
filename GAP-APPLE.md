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
3. **Capabilities**: leave everything off for v1 *unless* you ship Phase 9
   (push) — then enable **Push Notifications** here (and in Xcode, §6 of
   the roadmap). Nothing else is needed for the current feature set.
4. Save.

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
- **None** for the shipped feature set. Do **not** add entitlements you
  don't use — unused entitlements (push, associated domains, etc.) can
  trigger provisioning failures or review questions.
- Phase 9 (APNs) is the only thing that would add a capability later
  (Push Notifications + the `aps-environment` entitlement).

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
  Apple checks for these on social apps (Guideline 1.2). Confirm the app
  exposes content reporting/blocking, or add it before review.

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
  a social app. Verify these exist before review.
- **Broken demo login**: give reviewers working email/password creds.
- **Privacy label mismatch**: the declared data must match what the app
  actually sends (email, posts, identifiers).
- **Stale device-capability / icon alpha**: fixed by §3.3 and §3.5.2.
- **Incomplete metadata**: privacy policy URL is mandatory.

---

## 12. Quick pre-flight checklist
- [ ] Apple Developer membership active; agreements accepted (§1)
- [ ] App ID `com.interlinedlist.app` registered (§2)
- [ ] Automatic signing, team set, archive signs cleanly (§3.1)
- [ ] Build number incremented (§3.2)
- [ ] App icon has no warnings / no alpha (§3.3)
- [ ] `ITSAppUsesNonExemptEncryption=false` added (§3.5.1)
- [ ] `armv7` device capability replaced with `arm64` (§3.5.2)
- [ ] No unused entitlements/capabilities (§3.6)
- [ ] App Store Connect record + Free pricing + privacy/support URLs (§4)
- [ ] Content reporting / blocking present for UGC (§5.4)
- [ ] iPhone 6.9"/6.5" screenshots + description (§6)
- [ ] Archive uploaded; build processed (§7)
- [ ] TestFlight smoke test on device + demo login (§8)
- [ ] App Privacy label completed; review notes with demo creds (§9)
