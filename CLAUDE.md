# CLAUDE.md

Guidance for Claude Code in this repo. Follow it exactly — it overrides default behavior.

## Project

**InterlinedList** — native iOS/SwiftUI social list-sharing app talking to the `interlinedlist.com` API (auth, feed/compose, nested lists, documents, follows, organizations).

- Swift 5.9+, SwiftUI (UIKit only for keyboard dismissal + `ASWebAuthenticationSession`/`UIApplication` OAuth). Minimum target **iOS 17**.
- **No third-party dependencies** — Apple frameworks only.
- API base `https://interlinedlist.com`, overridable via `ILAPIBaseURL` in `Info.plist` (empty = production).
- Layout: `InterlinedList/{Models,Views,Services}` + `InterlinedListApp.swift`; tests in `InterlinedListTests/{APIClientTests,ModelTests,ServiceTests,E2E}`.

## The non-obvious rules (getting these wrong fails silently)

- **Three coders in `APIClient`, chosen per endpoint** — the most common bug:
  - `decoder` — `convertFromSnakeCase`, all responses.
  - `encoder` (`convertToSnakeCase`) via `post`/`put`/`patch` — snake_case bodies.
  - `camelCaseEncoder` (plain) via `postCamel`/`putCamel`/`patchCamel` — the **many** camelCase endpoints (messages, lists, orgs, watchers, identities, change-email, …). Check the existing method before adding one.
- **401 ≠ logged out.** Some endpoints only accept session cookies and reject a valid Bearer. `APIClient` throws `APIError.status(401)`; views call `authState.handleUnauthorized()`, which re-validates `GET /api/user` and only logs out if *that* 401s. Never `logout()` on a feature-endpoint 401.
- **Token storage: Keychain only** (`KeychainService`), never `UserDefaults`. Deep-link token query items are secrets — never log them.
- **Adding a `.swift` file:** no synced groups — register it in `project.pbxproj` (the `xcodeproj` Ruby gem) or it won't compile into the target.

## Build & Test

- Pin a concrete simulator **UDID** — `name=iPhone 16` alone is ambiguous across runtimes (`xcrun simctl list devices`).
- **Parallelization is disabled** (`InterlinedList.xctestplan`, `parallelizable:false`): the E2E suite shares a static login token that parallel cloned sims break. `-parallel-testing-enabled NO` is reinforcement; keep the plan setting in sync.
- Unit tests stub HTTP via `MockURLSession` (`stub`/`enqueue`) — no network.
- E2E tests (`InterlinedListTests/E2E`) hit the **live** API, **read-only**; auto-`XCTSkip` unless `INTERLINEDLIST_EMAIL`/`INTERLINEDLIST_PASSWORD` are set (process env or a gitignored `.env`). Network-flaky — for a deterministic run add `-skip-testing:InterlinedListTests/E2EReadOnlyTests`.
- CI (`.github/workflows/ios.yml`) **builds only** (no tests) on push/PR to `main`, signing disabled.

```bash
# Build (pin a UDID)
xcodebuild -scheme InterlinedList -destination 'platform=iOS Simulator,id=<UDID>' build
# Full suite, serialized
xcodebuild -scheme InterlinedList -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO test
# One class/method
xcodebuild test -scheme InterlinedList -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:InterlinedListTests/APIClientMessagesTests
```

## Coding standards (SOLID + KISS)

- One `View` renders one thing; one `Service` owns one domain; `APIClient` is HTTP-only. Depend on protocols (`URLSessionProtocol`) so it's testable without a network.
- **No force-unwrap** (`!`) in production paths. **No `DispatchQueue.main.async`** — use `@MainActor`.
- **No comments** unless the "why" is non-obvious. Mark view/service internals `private`.
- Every `View` file has a `#Preview`; every non-obvious interactive element has `.accessibilityLabel`.
- Lists nest via **`UserList.parentId`** — `""` and `nil` both mean "no parent" (see `ListTreeNode.buildTree`). List folders no longer exist; documents still have folders (below).

## Gotchas (current)

- **Document folders are path-scoped, not query/body-scoped.** `GET`/`POST /api/documents` are root-only (GET ignores `?folderId`; POST has no `folderId`). Folder contents = `GET /api/documents/folders/{id}/documents`; create-in-folder = `POST .../folders/{id}/documents`; only `PATCH /api/documents/{id}` takes `folderId` to move. Wrong route silently drops the doc to root.
- **GitHub-backed lists are editable via the standard `/api/lists/:id/data` routes** — they proxy to GitHub Issues (POST→create, PUT→patch, DELETE→close; a row's `id` **is** the issue number). Updates must send the **FULL row**: the backend rebuilds the issue and defaults a missing required `title` to `"Untitled"`, so a partial `PUT` renames the issue. Use `updateItem` (full row), not `updateRow`; see `ListDetailView.setGitHubState`.
- **GitHub schema + response shapes:** the server returns the synthetic schema in `GET /api/lists/:id` `properties` (`isReadOnly`, `state` as a `select`); `ListPropertyDef.gitHubIssueSchema()` is a client fallback when it's empty. Row-mutation responses return the saved row under **`data`**, not `row`. Rows headline via `ListPropertyDef.primaryDisplayField(from:)`, not `schema.first`.

## Reference docs

- `App-Store-Deployment.md` / `App-Store-Deployment-Checklist.md` — submission status, credentials/assets, pre-flight checklist.
- `the-gaps.md` — merged iOS↔web parity/gap doc (iOS defects + backend asks, paste-ready prompts). `the-gaps-access.md` — access/subscription gating notes.

## Subagents & skills (`.claude/`)

- Agents: `swift-dev` (feature/bugfix Swift), `qa-screenshotter` (sim screenshots + smoke tests), `release-manager` (submission readiness).
- Skills: `/comment-and-commit`, `/commit-and-pr`, `/unit-test`, `/e2e-test`, `/ios-review`, `/solid-check`.
- **Verification is mandatory:** build + relevant tests must pass before any work is reported done. Do isolated feature work in a git worktree (see `/comment-and-commit`).
