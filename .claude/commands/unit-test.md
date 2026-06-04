# /unit-test

Write and run unit tests for the specified Swift file, method, or feature. If no argument is given, run the full test suite and report results.

Usage:
- `/unit-test` — run the full suite
- `/unit-test APIClient messages` — write + run tests for the messages section of APIClient
- `/unit-test Models/List.swift` — write + run tests for List model logic
- `/unit-test forgot-password` — write + run tests for a named feature

---

## Steps

### 1. Locate or create the test target

```bash
ls InterlinedListTests/ 2>/dev/null || echo "TEST TARGET MISSING"
```

If `InterlinedListTests/` does not exist, create the directory and a minimal test harness:

```bash
mkdir -p InterlinedListTests/Fixtures
mkdir -p InterlinedListTests/APIClientTests
mkdir -p InterlinedListTests/ModelTests
```

Create `InterlinedListTests/MockURLSession.swift` if it does not exist:

```swift
import Foundation
@testable import InterlinedList

final class MockURLSession: URLSession {
    private var stubbedData: Data = Data()
    private var stubbedStatusCode: Int = 200
    private(set) var lastRequest: URLRequest?
    private(set) var requestHistory: [URLRequest] = []

    func stub(data: Data, statusCode: Int) {
        stubbedData = data
        stubbedStatusCode = statusCode
    }

    func stub(json: String, statusCode: Int = 200) {
        stubbedData = Data(json.utf8)
        stubbedStatusCode = statusCode
    }

    override func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        requestHistory.append(request)
        let url = request.url ?? URL(string: "https://interlinedlist.com")!
        let response = HTTPURLResponse(url: url, statusCode: stubbedStatusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (stubbedData, response)
    }
}
```

Also add `InterlinedListTests/InterlinedListTests.swift` as the entry point if missing (Xcode requires at least one file with `import XCTest`).

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
                            createdAt: "2024-01-01T00:00:00Z", updatedAt: nil, itemCount: nil)
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.name, "Root")
    }

    func test_buildTree_listWithEmptyFolderIdTreatedAsRoot() {
        var list = UserList(id: "1", name: "L", description: nil, folderId: "",
                            createdAt: "2024-01-01T00:00:00Z", updatedAt: nil, itemCount: nil)
        let nodes = ListTreeNode.buildTree(folders: [], lists: [list])
        XCTAssertEqual(nodes.count, 1)
    }
}
```

### 4. Add new files to the Xcode test target

After writing test files, verify they appear in `project.pbxproj`:
```bash
grep -l "InterlinedListTests" InterlinedList.xcodeproj/project.pbxproj | head -1
```

If they are missing, add them. The easiest approach is to add an explicit file reference and build phase entry to `project.pbxproj`, or instruct the user to drag the file into Xcode under the test target.

### 5. Run the tests

```bash
xcodebuild -scheme InterlinedList \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test 2>&1 | grep -E '(error:|Test Suite|Test Case|passed|failed|BUILD)'
```

### 6. Report results

Output a summary:

```
Tests written:   N
Tests passed:    N
Tests failed:    N (list each with file:line and failure message)
Coverage gaps:   List any methods/branches not covered and why they were skipped
```

If any test fails, diagnose and fix before reporting done.
