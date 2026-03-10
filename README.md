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

- **"Error creating the CFMessagePort needed to communicate with PPT"** — Comes from Apple’s internal PPT (Performance Power Tools) in UIKit. It’s a known simulator/device message, not from this app, and doesn’t affect behavior. Clean build (Shift+Cmd+K), restart Xcode/simulator, or update Xcode/iOS if it bothers you.
- **"Failed to send CA Event for app launch measurements … FirstFramePresentationMetric"** — The system tries to report launch metrics and sometimes fails (e.g. in simulator). Also not from app code and safe to ignore.
