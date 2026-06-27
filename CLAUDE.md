# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**InterlinedList** is a native iOS/SwiftUI social list-sharing app that connects to the `interlinedlist.com` backend API. Users authenticate (email/password or OAuth), compose messages, browse a feed, manage nested lists/folders and documents, follow people, and join organizations.

- **Language:** Swift 5.9+
- **UI framework:** SwiftUI (UIKit only via `UIResponder` for keyboard dismissal and `ASWebAuthenticationSession`/`UIApplication` for OAuth presentation)
- **Minimum target:** iOS 17 (uses `ContentUnavailableView`, `NavigationStack`, `onChange(of:_:)` two-param form)
- **No third-party dependencies** — pure Apple frameworks only
- **API base:** `https://interlinedlist.com` (overridable via `ILAPIBaseURL` in `Info.plist`; empty string = production)

## Directory Layout

```
InterlinedList/
  Models/          # Codable value types — no logic beyond computed properties
  Views/           # SwiftUI views and subviews — one public struct per file (~34 files)
  Services/        # APIClient, AuthState, AppDataStore, DataCache, KeychainService,
                   #   OAuthCoordinator, URLSessionProtocol
  InterlinedListApp.swift   # @main entry; wires env objects + deep-link handling
InterlinedListTests/
  APIClientTests/  # Per-domain HTTP tests using MockURLSession
  ModelTests/      # Codable round-trip + decoding-quirk tests
  ServiceTests/    # KeychainService etc.
  E2E/             # Read-only live-API smoke tests, gated on credentials
InterlinedList.xcodeproj/
InterlinedList.xctestplan   # Single test target; parallelization disabled (see Build & Test)
Resources/         # Logo assets, SVGs
.claude/           # agents/ (subagents), commands/ (slash-command skills)
GAP-*.md           # Living design/roadmap docs (see "Reference docs")
```

## Architecture

### Dependency injection & app composition
`InterlinedListApp` owns three `@StateObject`s injected at the root and consumed via `@EnvironmentObject` throughout the view tree:
- **`AuthState`** — session/user lifecycle (`@MainActor ObservableObject`).
- **`AppDataStore`** — central cached data layer for feed, lists, documents, and badge counts.
- **`AppRouter`** — holds `pendingDeepLink`; drives sheet presentation for custom-scheme URLs.

When `authState.hasToken` flips to `false`, the app calls `store.reset()` to clear cached data.

### `APIClient` — HTTP only
- `final class` singleton (`shared`) with an **injectable `URLSessionProtocol`** so tests swap in `MockURLSession` without subclassing `URLSession` (its async `data(for:)` lives in an extension and can't be overridden).
- Holds the Bearer token in memory (`setBearerToken`); does **not** own auth state or touch the UI.
- **Three coders, chosen per endpoint** — getting this wrong is the most common bug:
  - `decoder` — `convertFromSnakeCase` for all responses.
  - `encoder` (`convertToSnakeCase`) via `post`/`put`/`patch` — for snake_case request bodies.
  - `camelCaseEncoder` (plain) via `postCamel`/`putCamel`/`patchCamel` — for endpoints that expect **camelCase** bodies. **Many** endpoints use the camel variants (messages, lists, organizations, watchers, identities, change-email, …), not just `/api/messages`. Check the existing method before adding a new one.
- All requests funnel through `perform(_:)` → `checkResponse(_:_:)`, which throws typed `APIError` (`.status(401)`, `.server(msg)` from `{"error": ...}` bodies, `.conflict`, `.decoding`, `.network`). `os.Logger` logs method/path/status (never tokens).

### Auth & the 401 contract (important)
A `401` does **not** automatically mean the session is dead. Some backend endpoints only accept session-cookie auth and reject a valid Bearer token. So:
- `APIClient` simply throws `APIError.status(401)`.
- Views catch it and call **`authState.handleUnauthorized()`**, which re-validates against `GET /api/user`. Only if `/api/user` *itself* returns 401 does it `logout()`. Network errors keep the user logged in.
- Follow this pattern for any new authenticated call — do not log the user out directly on a 401 from a feature endpoint.

### `AppDataStore` — prefetch + offline cache + optimistic updates
- `prefetchAll(userId:)` fans out feed/lists/documents/counts concurrently with a `TaskGroup`.
- Reads/writes a per-user on-disk cache via **`DataCache`** (JSON files under `Caches/ILDataCache/`, keyed `"<userId>_feed"` etc.) so screens render instantly from cache, then refresh.
- Mutations are **optimistic** (`removeList`, `insertDocument`, …) and immediately re-persist to cache.
- Swallows `APIError.status(401)` during background refresh (auth is handled elsewhere); only surfaces an error string when there's no cached data to show.

### OAuth & deep links
- **`OAuthCoordinator`** wraps `ASWebAuthenticationSession`, opening `/api/auth/<provider>/authorize?redirect_uri=interlinedlist://oauth/callback` and parsing the returned `?token=...`.
- Custom URL scheme is **`interlinedlist://`**. `InterlinedListApp.handleDeepLink` routes `reset-password`, `verify-email`, `verify-email-change` (oauth callbacks are captured by the session itself).
- `OAuthProvider.supportsNativeAuth` is `false` for **GitHub** — its backend callback sets a web cookie and redirects to `/dashboard` instead of the custom scheme, so the in-app session can't complete. GitHub sign-in is hidden until the backend adds a mobile branch.

### Models & dates
- `Codable` structs, logic limited to computed properties. Decode defensively — see Gotchas.
- Dates stored as `String` (ISO 8601); formatted in the view layer (`ISO8601DateFormatter` → `RelativeDateTimeFormatter`).

## Design principles (SOLID + KISS)
- **SRP:** one `View` renders one thing; one `Service` owns one domain; `APIClient` is HTTP-only.
- **DIP:** services/view-models depend on protocols (`URLSessionProtocol`), so they're testable without a live network.
- **ISP:** keep protocols narrow; pass a closure or thin wrapper rather than a whole service into a view.
- **KISS:** flat `@State` over view models for simple screens; prefer `task {}`, `.refreshable {}`, `@EnvironmentObject` over custom schedulers; `async/await` over Combine unless Apple's built-ins fall short.

## Build & Test

Notes:
- `name=iPhone 16` alone is **ambiguous** across installed runtimes and can fail to resolve. Pin a concrete simulator UDID (`xcrun simctl list devices`) for reliable runs.
- **Parallelization is disabled in `InterlinedList.xctestplan`** (`parallelizable: false`). The E2E suite shares a `static` login token across tests to avoid re-hitting the rate-limited login endpoint; parallel runs use cloned simulators that don't share that state. The `-parallel-testing-enabled NO` flag below is therefore redundant reinforcement, not the source of truth — keep the plan setting in sync if you change this.

```bash
# Build for simulator
xcodebuild -scheme InterlinedList \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' build

# Run the full test suite (pin a UDID; serialize for stability)
xcodebuild -scheme InterlinedList \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' \
  -parallel-testing-enabled NO test

# Run a single test class or method
xcodebuild test -scheme InterlinedList \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' \
  -only-testing:InterlinedListTests/APIClientMessagesTests
# …/APIClientMessagesTests/testPostMessageUsesCamelCase  (single method)

# List simulators
xcrun simctl list devices --json | jq '.devices | to_entries[] | select(.value | length > 0)'
```

- **Unit tests** stub HTTP through `MockURLSession` (`stub`/`enqueue` for sequenced responses) — no network needed.
- **E2E tests** (`InterlinedListTests/E2E`) hit the **live** API but are strictly **read-only**. They auto-`XCTSkip` unless `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are present, read from process env (Xcode scheme Test action or CI) or a gitignored `.env` at repo root (`EnvLoader`).
- **CI** (`.github/workflows/ios.yml`) **builds only** (no tests) on push/PR to `main`, with code signing disabled.

## Coding Standards

- **No comments** unless the "why" is non-obvious (hidden constraint, workaround, API quirk).
- **No force-unwrap** (`!`) in production paths — use `guard`, `if let`, or `try?` with a meaningful fallback.
- **No `DispatchQueue.main.async`** — use `@MainActor` or `.receive(on: RunLoop.main)`.
- **Accessibility:** every interactive element needs `.accessibilityLabel` if the label isn't obvious from context.
- **Preview:** every `View` file should have a `#Preview` block.
- Mark view-internal helpers `private`; mark service internals `private`/`fileprivate`.

## Common Gotchas

- **camelCase vs snake_case bodies:** use the right encoder/helper (`postCamel` family for camelCase endpoints). Mismatches fail silently server-side. See APIClient architecture above.
- **Don't log out on a feature-endpoint 401** — route through `authState.handleUnauthorized()` (re-validates against `/api/user`).
- **Empty-string parents:** `ListFolder.parentId` and `UserList.folderId` may arrive as `""` instead of `null` — treat both as "no parent."
- **`listsAndFolders()`** issues `GET /api/folders` then `GET /api/lists` in sequence; errors from either propagate (the UI sees a real error, not an empty list).
- **Document folders are path-scoped, not query/body-scoped.** `GET /api/documents` and `POST /api/documents` are **root-only** (the GET ignores `?folderId=`; the POST has no `folderId` field). A folder's contents come from `GET /api/documents/folders/{id}/documents`, and creating in a folder is `POST /api/documents/folders/{id}/documents`. Only `PATCH /api/documents/{id}` takes `folderId` (camelCase) to move a doc. Using the wrong route silently drops the folder and the doc lands at root.
- **Token storage:** Keychain only (`KeychainService`); never `UserDefaults`. Token query items from deep links are sensitive — never log them.
- **Adding a file to the project:** there are no synced/file-system groups — a new `.swift` file must be manually registered in `project.pbxproj` (use the `xcodeproj` Ruby gem) or it won't compile into the target.

## Reference docs

- `GAP-ENDPOINTS.md` — live but under-documented/ambiguous API contracts the client had to guess or decode defensively.
- `GAP-NEXT-STEPS.md` — iOS-side implementation roadmap / punchlist.
- `GAP-APPLE.md` — App Store signing & submission checklist tailored to this app.
