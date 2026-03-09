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
