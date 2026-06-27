# /ios-review

Perform a focused code review of the Swift/SwiftUI changes on the current branch against `main`.

## Steps

1. **Identify changed Swift files**
   ```bash
   git diff main...HEAD --name-only | grep '\.swift$'
   ```

2. **Read each changed file in full** using the Read tool.

3. **Review against this checklist:**

   ### Architecture (SOLID / KISS)
   - [ ] Single Responsibility — does each type own exactly one concern?
   - [ ] No view directly calls `APIClient.shared` when `AuthState` or a service should mediate it
   - [ ] No logic (network calls, business rules) embedded inside `var body: some View`
   - [ ] Protocols used to invert dependencies where testability matters
   - [ ] No premature abstractions — is each helper used 3+ times?

   ### Swift idioms
   - [ ] No force-unwrap (`!`) on production paths
   - [ ] No `DispatchQueue.main.async` — uses `@MainActor` or `MainActor.run {}`
   - [ ] Async work uses `async/await` + SwiftUI task modifiers, not manual `DispatchQueue`
   - [ ] `Codable` models are pure value types with no networking or SwiftUI imports

   ### Project-specific
   - [ ] POST `/api/messages` body encoded with `camelCaseEncoder`, not default snake-case encoder
   - [ ] Empty-string `folderId` / `parentId` treated same as `nil`
   - [ ] Tokens stored in Keychain only — no `UserDefaults`
   - [ ] New `View` files include a `#Preview` block
   - [ ] Interactive elements have `.accessibilityLabel` where label isn't self-evident

   ### Error handling
   - [ ] Services throw `APIError`; no silent swallowing
   - [ ] Views surface errors in user-facing `String?` state, not `print()` only
   - [ ] 401 responses call `authState.handleUnauthorized()`

   ### Code quality
   - [ ] No unnecessary comments (only "why", never "what")
   - [ ] No dead code, unused variables, or leftover `TODO` without a tracking issue

4. **Summarize findings** as:
   - Blockers (must fix before merge)
   - Suggestions (non-blocking improvements)
   - Positives (good patterns worth noting)

5. **Run a build** to confirm there are no compilation errors:
   ```bash
   xcodebuild -scheme InterlinedList \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     build 2>&1 | grep -E '(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)'
   ```