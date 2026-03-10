# InterlinedList iOS

iPhone app for [InterlinedList](https://interlinedlist.com): sign in with email/password (sync token), view the feed, post and reply to messages, and switch between feed, lists, documents, and profile via a top navigation bar.

## Requirements

- Xcode 15+ (iOS 17 SDK)
- iOS 17+ device or simulator

## Open and run

1. Open `InterlinedList.xcodeproj` in Xcode.
2. Choose an iPhone simulator or a connected device.
3. Press **Run** (⌘R).

## Navigation

A **top bar** (tab-style) runs across the app with four items, left to right:

- **Home** – Messages feed. Tap the pencil in the toolbar to compose a new post.
- **Lists** – Placeholder (lists not yet implemented in the app).
- **Documents** – Placeholder (documents not yet implemented in the app).
- **Profile** – User avatar and display name; **Log out** is here.

## Features

- **Login / Register** – Email and password; token is stored in Keychain so you stay logged in.
- **Feed (Home)** – Messages from the site with pull-to-refresh and infinite scroll. Each message shows:
  - Author, date, content, and a lock icon when the message is private.
  - Optional **previews** (link cards, images, video) with a “Show previews” toggle at the top of the feed.
  - **Reply** and **Delete** (Delete only for your own messages). Reply opens a sheet to post a reply.
- **Compose** – Opened from the feed via the pencil button. Text posts with:
  - **Public** toggle (default comes from your account setting).
  - **Character count** from your account’s max message length.
  - **Advanced bar** (gear): toggles a row of icons (image, video, Mastodon, Bluesky, LinkedIn, calendar). Bar visibility default comes from your “Show advanced post settings” setting. Icon actions are not implemented yet.
- **Profile** – Avatar, display name, username, and Log out.

## Configuration

- **API base URL** – The app uses `https://interlinedlist.com` by default. To use another instance (e.g. local or staging), set the `ILAPIBaseURL` key in `Info.plist` to the base URL (e.g. `http://localhost:3000`). Leave it empty to use production.

## Known console messages (safe to ignore)

These come from the system or simulator, not from app logic. They do not indicate bugs in this app.

- **"Error creating the CFMessagePort needed to communicate with PPT"** — Apple’s internal PPT in UIKit. Known simulator/device message; doesn’t affect behavior.
- **"Failed to send CA Event for app launch measurements … FirstFramePresentationMetric"** — System launch metrics sometimes fail in simulator. Safe to ignore.
- **"[RTIInputSystemClient …] perform input operation requires a valid sessionID"** — System text input/emoji (RTI) can log this when the keyboard is involved during a transition. The app dismisses the keyboard before presenting reply/delete so this is less likely; if it still appears, it’s system-only and safe to ignore.
- **"Unable to simultaneously satisfy constraints"** involving **SystemInputAssistantView**, **UIRemoteKeyboardPlaceholderView**, **assistantHeight** — These are in the system keyboard/input assistant UI. iOS recovers by breaking a constraint; no app fix. Dismissing the keyboard before opening sheets/alerts can reduce how often it happens.
- **"nw_endpoint_flow_failed_with_error"**, **"nw_connection_copy_*"**, **"Socket is not connected"** — Low-level Network framework logs from failed or cancelled connections (e.g. network unreachable, request cancelled). Can appear when the system or app cancels requests. Safe to ignore unless the app’s own API calls are failing in the UI.
