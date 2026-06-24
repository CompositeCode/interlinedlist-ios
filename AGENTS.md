# InterlinedList iOS — Codex Guide

## Project Overview

**InterlinedList** is a native iOS/SwiftUI social list-sharing app that connects to the `interlinedlist.com` backend API. Users authenticate, compose messages, browse a feed, and manage nested lists and folders.

- **Language:** Swift 5.9+
- **UI framework:** SwiftUI (no UIKit except `UIResponder` for keyboard dismissal)
- **Minimum target:** iOS 17 (uses `ContentUnavailableView`, `NavigationStack`)
- **No third-party dependencies** — pure Apple frameworks only
- **API base:** `https://interlinedlist.com` (overridable via `ILAPIBaseURL` in `Info.plist`)

## Directory Layout

```
InterlinedList/
  Models/          # Codable value types — no logic beyond computed properties
  Views/           # SwiftUI views and subviews — one public struct per file
  Services/        # Networking (APIClient), auth state (AuthState), Keychain
InterlinedList.xcodeproj/
Resources/         # Logo assets, SVGs
.Codex/
  agents/          # Subagent definitions
  commands/        # Slash-command skills
```

## Architecture Principles

### SOLID in Swift/SwiftUI
- **Single Responsibility:** Each `View` renders one thing. Each `Service` owns one domain. `APIClient` handles HTTP only — no auth state, no UI.
- **Open/Closed:** Extend behavior via new `View` structs or protocol conformances, not by editing existing ones.
- **Liskov:** Prefer `protocol` over inheritance; conform only when you can fully satisfy the contract.
- **Interface Segregation:** Keep protocols narrow. Don't force a `View` to depend on a full service when only one method is needed — pass closures or a thin wrapper instead.
- **Dependency Inversion:** Services and view models depend on protocols, not concrete types, so they are testable without a live network.

### KISS
- Flat `@State` over elaborate view models for simple screens.
- Prefer built-in SwiftUI idioms (`task {}`, `.refreshable {}`, `@EnvironmentObject`) over custom schedulers.
- No reactive third-party libraries — use `async/await` and `Combine` only when Apple's built-ins fall short.

### Key Patterns
- **`APIClient`** is a `final class` singleton (`shared`) with injectable `URLSession` for testing.
- **`AuthState`** is a `@MainActor ObservableObject` injected at the root and propagated via `@EnvironmentObject`.
- **Models** are `Codable` structs. Use `snake_case ↔ camelCase` via `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`, except for endpoints that already send camelCase — use the dedicated `camelCaseEncoder`.
- **Error handling:** Propagate `APIError` from services; views catch and surface human-readable strings. Don't swallow errors silently.
- **Dates:** Stored as `String` (ISO 8601) in models; formatted in the view layer (`ISO8601DateFormatter` → `RelativeDateTimeFormatter`).

## Build & Test

```bash
# Build for simulator
xcodebuild -scheme InterlinedList -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (when test target exists)
xcodebuild -scheme InterlinedList -destination 'platform=iOS Simulator,name=iPhone 16' test

# List available simulators
xcrun simctl list devices --json | jq '.devices | to_entries[] | select(.value | length > 0)'
```

## Coding Standards

- **No comments** unless the "why" is non-obvious (hidden constraint, workaround, API quirk).
- **No force-unwrap** (`!`) in production paths — use `guard`, `if let`, or `try?` with a meaningful fallback.
- **No `DispatchQueue.main.async`** — use `@MainActor` or `.receive(on: RunLoop.main)`.
- **Accessibility:** Every interactive element needs `.accessibilityLabel` if the label isn't obvious from context.
- **Preview:** Every `View` file should have a `#Preview` macro block.
- Mark view-internal helpers `private`; mark service internals `private` or `fileprivate`.

## Common Gotchas

- The `/api/messages` POST endpoint expects **camelCase** keys (`publiclyVisible`, `parentId`), not snake_case — use `camelCaseEncoder`, not the default `encoder`.
- `ListFolder.parentId` and `UserList.folderId` may arrive as `""` instead of `null` — treat both as "no parent."
- `APIClient.listsAndFolders()` issues two requests in sequence: `GET /api/folders`, then `GET /api/lists`. Errors from either call propagate to the caller. The endpoint is documented as live; if a stale deployment doesn't expose it, the UI will see a real error (not an empty folder list).
- Token is stored in Keychain via `KeychainService`; never store it in `UserDefaults`.
