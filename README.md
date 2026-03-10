# InterlinedList iOS

iPhone app for [InterlinedList](https://interlinedlist.com): sign in with email/password (sync token), view the feed, and post text messages.

## Requirements

- Xcode 15+ (iOS 17 SDK)
- iOS 17+ device or simulator

## Open and run

1. Open `InterlinedList.xcodeproj` in Xcode.
2. Choose an iPhone simulator or a connected device.
3. Press **Run** (⌘R).

## Features

- **Login / Register** – Email and password; token is stored in Keychain so you stay logged in.
- **Feed** – Lists messages from the site (pull to refresh).
- **Compose** – Text-only posts with an optional “Public” toggle.
- **Log out** – Via the profile menu in the top-right.

## Configuration

The app uses `https://interlinedlist.com` by default. To point at another instance, change the `baseURL` in `APIClient.swift` (or make it configurable via a build setting / plist).

## Known console messages (safe to ignore)

These come from the system or simulator, not from app logic. They do not indicate bugs in this app.

- **"Error creating the CFMessagePort needed to communicate with PPT"** — Apple’s internal PPT in UIKit. Known simulator/device message; doesn’t affect behavior.
- **"Failed to send CA Event for app launch measurements … FirstFramePresentationMetric"** — System launch metrics sometimes fail in simulator. Safe to ignore.
- **"[RTIInputSystemClient …] perform input operation requires a valid sessionID"** — System text input/emoji (RTI) can log this when the keyboard is involved during a transition. The app dismisses the keyboard before presenting reply/delete so this is less likely; if it still appears, it’s system-only and safe to ignore.
- **"Unable to simultaneously satisfy constraints"** involving **SystemInputAssistantView**, **UIRemoteKeyboardPlaceholderView**, **assistantHeight** — These are in the system keyboard/input assistant UI. iOS recovers by breaking a constraint; no app fix. Dismissing the keyboard before opening sheets/alerts can reduce how often it happens.
- **"nw_endpoint_flow_failed_with_error"**, **"nw_connection_copy_*"**, **"Socket is not connected"** — Low-level Network framework logs from failed or cancelled connections (e.g. network unreachable, request cancelled). Can appear when the system or app cancels requests. Safe to ignore unless the app’s own API calls are failing in the UI.
