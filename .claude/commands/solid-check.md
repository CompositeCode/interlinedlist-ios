# /solid-check

Audit the entire Swift codebase for SOLID principle violations and KISS anti-patterns. Report findings with file:line references and concrete fixes.

## Steps

1. **Collect all Swift source files**
   ```bash
   find InterlinedList -name '*.swift' | sort
   ```

2. **Read every file** using the Read tool.

3. **Apply each principle check:**

---

### S — Single Responsibility
Flag any type that does more than one thing:
- A `View` struct that also owns network state (has `URLSession` / `URLRequest` calls in `body` or `init`)
- A model struct that imports `SwiftUI` or `Foundation.URLSession`
- A service that manages both networking AND persistent state (e.g., token storage + HTTP)
- A view that handles 3+ unrelated user interactions without extracting sub-views

### O — Open/Closed
Flag modification hot-spots:
- `switch` statements on an enum where adding a new case forces edits in multiple files
- Large `if/else if` chains that dispatch to different behaviors — suggest a strategy/protocol pattern
- Any place a type's `init` takes a raw string to select behavior (use an enum instead)

### L — Liskov Substitution
Flag broken contracts:
- Protocol conformances that `fatalError` or `preconditionFailure` on any method
- Conformances that silently no-op methods declared as required by the protocol
- Subclasses (rare in this codebase) that change behavior in a way callers cannot anticipate

### I — Interface Segregation
Flag fat dependencies:
- A `View` that receives a full service (`APIClient`, `AuthState`, `AppDataStore`) but only uses one method/property — suggest passing a closure or narrow protocol instead
- A protocol with 5+ requirements where conformers only need 1-2 — suggest splitting

### D — Dependency Inversion
Flag concrete dependencies that block testing:
- Types that instantiate `APIClient.shared` directly inside `init` without an injection point
- Types that call `KeychainService.loadToken()` directly instead of accepting a token provider
- `@StateObject` or `@ObservedObject` created with concrete types where a protocol would allow mocking

---

### KISS Anti-patterns
- `ObservableObject` view model introduced for a view with only 1-2 `@Published` properties — prefer `@State`
- Combine pipeline where a plain `async/await` call would work
- Generic helper functions used in only one place
- Nested types more than 2 levels deep without clear reason
- Comment blocks explaining what the code does (rename the symbol instead)

---

4. **Output format**

For each violation, output one block:

```
[PRINCIPLE] File.swift:line
Problem: <one sentence>
Fix:     <one sentence or short code snippet>
```

Group by principle. End with a **Score** section:

```
S: X violations
O: X violations
L: X violations
I: X violations
D: X violations
KISS: X violations
Overall: PASS (0 blockers) | NEEDS WORK (N blockers)
```

A "blocker" is any violation that would actively complicate adding a new feature or writing a unit test.