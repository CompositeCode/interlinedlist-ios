# /e2e-test

Write and run end-to-end tests for one or more user-facing flows using XCUITest. If no argument is given, run the full XCUITest suite.

Usage:
- `/e2e-test` — run all XCUITests
- `/e2e-test login` — write + run login/logout flow tests
- `/e2e-test compose` — write + run message compose flow tests
- `/e2e-test lists` — write + run list management flow tests

---

## Scope of e2e tests in this project

XCUITest exercises the live app UI against the **real API** (`https://interlinedlist.com`). Tests must:
- Use a dedicated test account (credentials stored in `InterlinedListUITests/TestCredentials.swift`, never committed to git — see setup below).
- Be idempotent: clean up any data they create.
- Be independent: each test method starts from the login screen (log out in `tearDown`).

E2e tests are **not** a substitute for unit tests. Use them only for critical user flows where a regression in the wiring (view → service → API → UI update) would be invisible to unit tests.

---

## Steps

### 1. Locate or create the UI test target

```bash
ls InterlinedListUITests/ 2>/dev/null || echo "UI TEST TARGET MISSING"
```

If `InterlinedListUITests/` does not exist, create it:

```bash
mkdir -p InterlinedListUITests
```

Create `InterlinedListUITests/TestCredentials.swift` **only if it does not already exist**, and add it to `.gitignore`:

```swift
// NOT committed to git — fill in manually or via CI secrets
enum TestCredentials {
    static let email    = "uitest@example.com"
    static let password = "changeme"
    static let username = "uitestuser"
}
```

Check `.gitignore`:
```bash
grep "TestCredentials" .gitignore || echo "InterlinedListUITests/TestCredentials.swift" >> .gitignore
```

Create a shared `BaseUITestCase.swift`:

```swift
import XCTest

class BaseUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        login()
    }

    override func tearDown() {
        logout()
        super.tearDown()
    }

    func login() {
        let emailField = app.textFields["Email"]
        guard emailField.waitForExistence(timeout: 5) else {
            return  // already logged in
        }
        emailField.tap()
        emailField.typeText(TestCredentials.email)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText(TestCredentials.password)
        app.buttons["Log in"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10),
                      "Tab bar did not appear after login")
    }

    func logout() {
        // Navigate to Profile tab and tap logout if present
        app.tabBars.buttons["Profile"].tap()
        if app.buttons["Log out"].exists {
            app.buttons["Log out"].tap()
        }
    }
}
```

### 2. Identify accessibility labels in the target flow

Before writing XCUITest selectors, read the relevant view file(s) to find `.accessibilityLabel` values and button/field labels used as identifiers.

```bash
grep -n "accessibilityLabel\|accessibilityIdentifier\|\.buttons\[" \
  InterlinedList/Views/<TargetView>.swift
```

If interactive elements are missing `.accessibilityIdentifier` that XCUITest needs to target reliably, add them to the source view now (do not add `.accessibilityLabel` purely for test targeting — use `.accessibilityIdentifier` instead, which is invisible to VoiceOver).

### 3. Write the XCUITest

One file per flow in `InterlinedListUITests/`. Examples:

**Login flow (`LoginUITests.swift`):**

```swift
import XCTest

final class LoginUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func test_login_validCredentials_showsTabBar() {
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText(TestCredentials.email)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText(TestCredentials.password)
        app.buttons["Log in"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    func test_login_wrongPassword_showsErrorMessage() {
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText(TestCredentials.email)
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("wrongpassword")
        app.buttons["Log in"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Invalid'"))
                          .firstMatch.waitForExistence(timeout: 5))
    }
}
```

**Compose flow (`ComposeUITests.swift`):**

```swift
final class ComposeUITests: BaseUITestCase {
    func test_compose_postMessage_appearsInFeed() throws {
        let unique = "UITest-\(Int(Date().timeIntervalSince1970))"
        app.tabBars.buttons["Home"].tap()
        app.navigationBars.buttons["compose"].tap()   // accessibilityIdentifier on compose button
        let textEditor = app.textViews.firstMatch
        XCTAssertTrue(textEditor.waitForExistence(timeout: 5))
        textEditor.tap()
        textEditor.typeText(unique)
        app.buttons["Post"].tap()
        XCTAssertTrue(app.alerts.buttons["OK"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        // Verify the message appears in the feed
        XCTAssertTrue(app.staticTexts[unique].waitForExistence(timeout: 10))
    }
}
```

**Lists flow (`ListsUITests.swift`):**

```swift
final class ListsUITests: BaseUITestCase {
    func test_createList_appearsInListsTab() {
        let name = "UITest-List-\(Int(Date().timeIntervalSince1970))"
        app.tabBars.buttons["Lists"].tap()
        app.navigationBars.buttons["Add"].tap()
        app.textFields["List name"].tap()
        app.textFields["List name"].typeText(name)
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    func test_deleteList_removedFromListsTab() {
        // Create a list first, then delete it
        let name = "UITest-Delete-\(Int(Date().timeIntervalSince1970))"
        app.tabBars.buttons["Lists"].tap()
        app.navigationBars.buttons["Add"].tap()
        app.textFields["List name"].tap()
        app.textFields["List name"].typeText(name)
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
        // Swipe to delete
        app.staticTexts[name].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts[name].waitForExistence(timeout: 3))
    }
}
```

### 4. Handle `--uitesting` launch argument in the app

In `InterlinedListApp.swift` or `RootView.swift`, check for the flag and skip any onboarding or animation that would interfere with tests:

```swift
// In app init or scene setup:
if ProcessInfo.processInfo.arguments.contains("--uitesting") {
    // Disable animations for deterministic test timing
    UIView.setAnimationsEnabled(false)
}
```

### 5. Run the tests

Boot the simulator first (avoids a cold-boot timeout):
```bash
xcrun simctl boot "iPhone 16" 2>/dev/null || true
```

Run the UI test scheme:
```bash
xcodebuild -scheme InterlinedList \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:InterlinedListUITests \
  test 2>&1 | grep -E '(error:|Test Suite|Test Case|passed|failed|BUILD)'
```

To run a single test class:
```bash
xcodebuild -scheme InterlinedList \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:InterlinedListUITests/LoginUITests \
  test 2>&1 | grep -E '(Test Case|passed|failed|error:)'
```

### 6. API-level smoke test (optional, fast)

For flows that are purely API logic (no UI assertions needed), the existing `scripts/test_api.py` can serve as a faster complement to XCUITest:

```bash
python3 scripts/test_api.py 2>&1 | tail -20
```

Use this as a pre-flight check before launching the simulator.

### 7. Report results

```
Flow tested:     <name>
Tests written:   N
Tests passed:    N
Tests failed:    N
  - <TestClass/testMethod>: <failure message> at <file:line>
Accessibility gaps: Any interactive elements that lacked identifiers and were added
Cleanup:         Any test data created (listed) — confirm deleted in tearDown
```

If any test fails due to missing `.accessibilityIdentifier` on a view element, add it to the source view and note the change.
