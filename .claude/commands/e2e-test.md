# /e2e-test

Add and run **read-only** end-to-end smoke tests against the live
`interlinedlist.com` API. If no argument is given, run the whole E2E suite.

Usage:
- `/e2e-test` — run the full E2E suite
- `/e2e-test documents` — add + run a read-only probe for the documents endpoints
- `/e2e-test <area>` — add + run a read-only probe for that API area

---

## What E2E means in this project (read this first)

There is **no XCUITest / UI-automation target** and no `TestCredentials.swift`.
The E2E suite is `InterlinedListTests/E2E/E2EReadOnlyTests.swift` — it drives the
real `APIClient` against production and asserts on responses. Hard rules:

- **Read-only.** Tests only **GET**. They never POST/PUT/PATCH/DELETE or otherwise
  mutate server state, so they're safe against the production account. Do **not**
  add a mutating probe here — if you need to exercise a write, mock it in a unit
  test (`/unit-test`) instead.
- **Credentials come from `EnvLoader`** (`InterlinedListTests/E2E/EnvLoader.swift`),
  which reads `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` from, in order:
  1. the process environment (Xcode scheme Test action env, or CI secrets), then
  2. a gitignored `.env` at the repo root.
- **Auto-skip without creds.** Every test begins with
  `try XCTSkipUnless(EnvLoader.hasCredentials, …)`, so a fresh checkout or a CI run
  without secrets skips cleanly instead of failing.
- **One login per run.** The suite logs in once and caches a `static` token
  (`sharedToken`) reused across every test, and caches a login failure so the rest
  skip fast rather than re-hitting the rate-limited login endpoint. Don't add
  per-test logins.

---

## Steps

### 1. Confirm the suite and credentials

```bash
ls InterlinedListTests/E2E/           # E2EReadOnlyTests.swift + EnvLoader.swift
grep -c . .env 2>/dev/null || echo "no .env — tests will XCTSkip unless env vars are set"
```

The suite and `EnvLoader` already exist — extend them, don't recreate them.

### 2. Add a read-only probe (if an area was named)

Add a new `func test_e2e_<area>_<expectation>() async throws` to
`E2EReadOnlyTests.swift`. `setUp()` already logs in and sets the bearer token on
`client`, so a test just calls a GET method and asserts. Pattern to mirror:

```swift
// MARK: - Documents (read-only)

func test_e2e_documents_rootListLoads() async throws {
    let docs = try await client.documents()          // GET /api/documents (root only)
    // Don't assert exact counts against a live account — assert shape/invariants.
    XCTAssertNoThrow(docs)
    for doc in docs { XCTAssertFalse(doc.id.isEmpty) }
}
```

Guidance:
- **Only call GET methods.** If the `APIClient` method you want to exercise
  mutates state, stop — cover it with a `MockURLSession` unit test instead.
- Assert on **invariants** (non-empty ids, decodable shape, expected optionals),
  not on exact live data that changes between runs.
- Respect the confirmed **public-browse namespace split** when probing public
  routes: `/api/user/:username/messages` (singular) vs
  `/api/users/:username/lists` (plural) — the wrong one 404s (see `the-gaps.md`).

### 3. Register the file (only if you added a new one)

You'll normally extend the existing file. If you add a *new* `.swift` file, it
must be registered in `project.pbxproj` (no synced groups) under the
`InterlinedListTests` target — use the `xcodeproj` Ruby gem, or drag it into Xcode.

### 4. Run the suite

Prefer XcodeBuildMCP `test_sim` scoped to the class. Raw fallback — pin a UDID and
serialize (the `.xctestplan` sets `parallelizable:false`; the shared static login
token breaks under parallel cloned simulators):

```bash
xcodebuild test -scheme InterlinedList \
  -destination 'platform=iOS Simulator,id=<SIM_UDID>' \
  -parallel-testing-enabled NO \
  -only-testing:InterlinedListTests/E2EReadOnlyTests \
  2>&1 | grep -E '(error:|Test Suite|Test Case|passed|failed|Skipped|BUILD)'
```

Run a single method with
`-only-testing:InterlinedListTests/E2EReadOnlyTests/<methodName>`.

> If every test reports **Skipped**, credentials aren't visible to the test
> process — set `INTERLINEDLIST_EMAIL`/`INTERLINEDLIST_PASSWORD` in the scheme's
> Test action env or add them to `.env` at the repo root.

### 5. Optional pre-flight: `scripts/test_api.py`

For a fast, simulator-free sanity check of API behavior before compiling the
suite:

```bash
python3 scripts/test_api.py 2>&1 | tail -20
```

### 6. Report results

```
Suite:            E2EReadOnlyTests
Ran / Skipped:    N ran, M skipped (creds present? yes/no)
Passed / Failed:  N / N
  - <testMethod>: <failure message> at <file:line>
New probes added: <list, all read-only>
```

If tests skipped for missing credentials, say so explicitly — a green "0 failed"
with everything skipped is **not** a passing E2E run.
