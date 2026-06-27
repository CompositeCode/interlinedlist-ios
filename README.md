# InterlinedList iOS

Native iOS app for [InterlinedList](https://interlinedlist.com) — a social list-sharing service. Sign in, browse a message feed, post and reply, and manage nested lists, documents, organizations, and your social graph. Built in SwiftUI with no third-party dependencies.

## Requirements

- Xcode 15+ (iOS 17 SDK)
- iOS 17+ device or simulator

## Open and run

1. Open `InterlinedList.xcodeproj` in Xcode.
2. Choose an iPhone simulator or a connected device.
3. Press **Run** (⌘R).

## Navigation

A **top bar** runs across the app with four sections plus a notifications bell:

- **Home** — Messages feed; tap the pencil to compose.
- **Lists** — Your lists and folders.
- **Documents** — Your documents and folders.
- **Profile** — Avatar, account details, social links, settings (gear), and Log out.
- **🔔 Bell** — Notifications, with a badge for unread notifications and pending follow requests.

An email-verification banner appears beneath the top bar until the account's email is verified.

## Features

### Accounts & auth
- **Email / password** sign-in (issues a sync token stored in the Keychain) and registration.
- **Forgot / reset password** and **email verification**, reachable via `interlinedlist://` deep links.
- **OAuth sign-in** via the system browser (`ASWebAuthenticationSession`) for Mastodon, Bluesky, LinkedIn, and Twitter. *(GitHub is hidden pending backend support for the native callback.)*
- **Linked accounts** management (subscribers).
- **Change email** and **delete account** from Settings.

### Feed & messages
- Feed with pull-to-refresh and infinite scroll; cached data renders instantly on launch, then refreshes.
- Each message shows author, date, content, a lock icon when private, and optional **previews** (link cards, images, video) behind a "Show previews" toggle.
- **Reply**, **edit**, and **delete** (your own messages); threaded conversation view.

### Compose
- **Public** toggle (default from your account setting) and a live **character count** (your account's max length).
- **Subscriber features**: image and video upload, **scheduled posts**, and cross-posting to linked Mastodon / Bluesky / LinkedIn accounts.

### Lists & documents
- Browse lists and documents as a tree; **search** within each.
- Create lists and documents; edit a list's **schema** (its columns/fields) and rows.
- **Nested folders** organize both (subscriber feature; free accounts see a flat view).
- List **connections** and **watchers**; public list/document detail views.

### Social & organizations
- **Followers / following**, **follow requests** (accept/decline).
- **Organizations** with member management.
- View other users' profiles.

### Settings & preferences
- Edit profile (display name, bio, avatar), theme (light/dark/system, applied app-wide), default post visibility, advanced-post-settings toggle, and notification preferences.

## Configuration

- **API base URL** — defaults to `https://interlinedlist.com`. To target another instance (local/staging), set `ILAPIBaseURL` in `Info.plist` (e.g. `http://localhost:3000`). Leave it empty for production.

## Testing

- **Unit tests** stub the network through `MockURLSession` — no connectivity required.
- **End-to-end tests** (`InterlinedListTests/E2E`) run **read-only** checks against the live API. They auto-skip unless credentials are provided via the Xcode scheme's Test action environment, or a gitignored `.env` at the repo root:
  ```
  INTERLINEDLIST_EMAIL=you@example.com
  INTERLINEDLIST_PASSWORD=...
  ```

Run from Xcode (⌘U) or via `xcodebuild` — see `CLAUDE.md` for command-line invocations and a note on pinning a simulator UDID.

## Known console messages (safe to ignore)

These come from the system or simulator, not from app logic, and do not indicate bugs:

- **"Error creating the CFMessagePort needed to communicate with PPT"** — Apple's internal PPT in UIKit; a known simulator/device message.
- **"Failed to send CA Event … FirstFramePresentationMetric"** — system launch metrics occasionally failing in the simulator.
- **"[RTIInputSystemClient …] perform input operation requires a valid sessionID"** — system text-input/emoji (RTI) logging during transitions. The app dismisses the keyboard before presenting sheets to reduce this.
- **"Unable to simultaneously satisfy constraints"** involving **SystemInputAssistantView** / **UIRemoteKeyboardPlaceholderView** / **assistantHeight** — system keyboard/input-assistant UI; iOS recovers by breaking a constraint.
- **"nw_endpoint_flow_failed_with_error"**, **"nw_connection_copy_*"**, **"Socket is not connected"** — low-level Network framework logs from cancelled/failed connections. Safe to ignore unless the app's own API calls are failing in the UI.

## Project guide

See `CLAUDE.md` for architecture, conventions, and build/test commands.
