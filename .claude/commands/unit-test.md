# /unit-test

Write and run unit tests for the specified Swift file, method, or feature. If no argument is given, run the full test suite and report results.

Usage:
- `/unit-test` — run the full suite
- `/unit-test APIClient messages` — write + run tests for the messages section of APIClient
- `/unit-test Models/List.swift` — write + run tests for List model logic
- `/unit-test forgot-password` — write + run tests for a named feature

---

## Steps

### 1. Use the existing test target and mock (already set up)

The `InterlinedListTests/` target already exists with this structure — add new tests into the matching folder, don't recreate anything:

```
InterlinedListTests/
  MockURLSession.swift      shared mock (conforms to URLSessionProtocol)
  Fixtures/                 JSON fixture files (.json) for decode tests
  APIClientTests/           one test file per APIClient domain section
  ModelTests/               Codable round-trip and logic tests
  ServiceTests/             KeychainService, AppDataStore, image upload, etc.
  E2E/                      read-only live-API smoke tests (see /e2e-test)
```

**`MockURLSession` already exists — reuse it.** It conforms to **`URLSessionProtocol`** (it does *not* subclass `URLSession`, whose async `data(for:)` lives in an extension and can't be overridden). It's injected via `APIClient(session:)` — `init(baseURL: String? = nil, session: URLSessionProtocol = URLSession.shared)`. Its API:

```swift
final class MockURLSession: URLSessionProtocol {
    private(set) var lastRequest: URLRequest?
    private(set) var requestHistory: [URLRequest] = []

    func stub(data: Data, statusCode: Int = 200)        // single response
    func stub(json: String, statusCode: Int = 200)
    func enqueue(json: String, statusCode: Int = 200)   // FIFO queue for sequenced responses
    func enqueue(data: Data, statusCode: Int = 200)

    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

### 2. Identify what needs testing

If an argument was given, read the specified file(s):
```bash
# Example: find changed Swift files if no specific target given
git diff main...HEAD --name-only | grep '\.swift$' | grep -v Tests
```

Read the source file and identify:
- Public/internal methods with branching logic (if/guard/switch/throw)
- `Codable` models — need encode/decode round-trip tests
- Computed properties with non-trivial logic
- Error paths — each `throw` site should have a corresponding test

Skip: `var body: some View`, pure pass-through getters, SwiftUI modifiers.

### 3. Write the tests

**APIClient method tests** — one `XCTestCase` subclass per MARK section, in `InterlinedListTests/APIClientTests/`:

```swift
import XCTest
@testable import InterlinedList

final class APIClientMessagesTests: XCTestCase {
    var sut: APIClient!
    var session: MockURLSession!

    override func setUp() {
        super.setUp()
        session = MockURLSession()
        sut = APIClient(session: session)
        sut.setBearerToken("tok")
    }

    // Happy path: correct URL path, method, and decoded result
    func test_messages_defaultParams_sendsCorrectRequest() async throws {
        session.stub(json: #"{"messages":[],"pagination":null}"#)
        _ = try await sut.messages()
        XCTAssertEqual(session.lastRequest?.url?.path, "/api/messages")
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    // 401 must throw .status(401)
    func test_messages_401_throwsStatusError() async throws {
        session.stub(data: Data(), statusCode: 401)
        do {
            _ = try await sut.messages()
            XCTFail("Expected APIError.status(401)")
        } catch APIError.status(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // Server error body is propagated
    func test_messages_serverError_throwsServerError() async throws {
        session.stub(json: #"{"error":"rate limited"}"#, statusCode: 429)
        do {
            _ = try await sut.messages()
            XCTFail("Expected APIError.server")
        } catch APIError.server(let msg) {
            XCTAssertEqual(msg, "rate limited")
        }
    }
}
```

**Model Codable tests** — in `InterlinedListTests/ModelTests/`:

```swift
final class UserListCodableTests: XCTestCase {
    func test_decode_mapsServerTitleToName() throws {
        let json = #"{"id":"1","title":"My List","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try JSONDecoder().decode(UserList.self, from: Data(json.utf8))
        XCTAssertEqual(list.name, "My List")
    }

    func test_decode_emptyParentIdTreatedAsNil() throws {
        let json = #"{"id":"1","title":"L","parentId":"","createdAt":"2024-01-01T00:00:00Z"}"#
        let list = try JSONDecoder().decode(UserList.self, from: Data(json.utf8))
        // folderId maps parentId; empty string is NOT nil at decode time — test the usage guard
        XCTAssertEqual(list.folderId, "")
        // The tree-builder treats "" as absent — verify that invariant here
        XCTAssertTrue((list.folderId ?? "").isEmpty)
    }
}
```

**Pure logic tests** (tree builder, helpers):

```swift
final class ListTreeNodeTests: XCTestCase {
    func test_buildTree_rootListWithNoFolder_appearsAtRoot() {
        let list = UserList(id: "1", name: "Root", description: nil, folderId: nil,
                            isPublic: nil, createdAt: "2024-01-01T00:00:00Z",
                            updatedAt: nil, itemCount: nil)
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Root")
    }

    func test_buildTree_listWithEmptyFolderIdTreatedAsRoot() {
        let list = UserList(id: "1", name: "L", description: nil, folderId: "",
                            isPublic: nil, createdAt: "2024-01-01T00:00:00Z",
                            updatedAt: nil, itemCount: nil)
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
    }
}
```

### 4. Register new test files in the Xcode target

There are no synced/file-system groups, so a new `.swift` file won't compile into the test target until it's added to `project.pbxproj`. After writing test files, confirm they're referenced:
```bash
grep -c "<NewTestFile>.swift" InterlinedList.xcodeproj/project.pbxproj
```
If it returns 0, register the file (and its build-phase entry) in `project.pbxproj` — use the `xcodeproj` Ruby gem for a reliable edit, or have the user drag the file into Xcode under the `InterlinedListTests` target.

### 5. Run the tests

Prefer XcodeBuildMCP `test_sim` (after `session_show_defaults`). Raw fallback — pin a UDID and serialize (the `.xctestplan` sets `parallelizable:false`; the E2E suite shares a static login token that parallel cloned sims would break):
```bash
xcodebuild -scheme InterlinedList \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' \
  -parallel-testing-enabled NO \
  test 2>&1 | grep -E '(error:|Test Suite|Test Case|passed|failed|BUILD)'
```
Run a single class/method with `-only-testing:InterlinedListTests/<Class>[/<method>]`.

### 6. Report results

Output a summary:

```
Tests written:   N
Tests passed:    N
Tests failed:    N (list each with file:line and failure message)
Coverage gaps:   List any methods/branches not covered and why they were skipped
```

If any test fails, diagnose and fix before reporting done.
