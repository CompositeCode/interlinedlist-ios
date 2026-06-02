# Plan 15 — Cross-Posting (Mastodon, Bluesky, LinkedIn)

## Status
The `ComposeView` already has stub buttons for Mastodon ("M"), Bluesky ("BS"), and LinkedIn ("in") in the advanced bar — all disabled. This plan wires them up end-to-end.

## Goal
Fetch the user's connected social identities, surface toggles in the advanced bar, and include the appropriate cross-post flags in the message POST body.

## Endpoint
`GET /api/user/identities` — returns connected provider accounts.

Expected response shape (inferred from API docs):
```json
{
  "identities": [
    { "provider": "mastodon", "providerId": "abc123", "displayName": "@user@mastodon.social" },
    { "provider": "bluesky", "providerId": "did:plc:...", "displayName": "@user.bsky.social" },
    { "provider": "linkedin", "providerId": "urn:li:...", "displayName": "User Name" }
  ]
}
```

## Files to Change

| File | Change |
|------|--------|
| `InterlinedList/Models/User.swift` | Add `SocialIdentity` model |
| `InterlinedList/Services/APIClient.swift` | Add `userIdentities()` method; add cross-post fields to `postMessage` |
| `InterlinedList/Views/ComposeView.swift` | Load identities; replace disabled stubs with real toggles |

## Step-by-Step

### 1. `Models/User.swift` — add `SocialIdentity`

```swift
struct SocialIdentity: Identifiable, Codable {
    let id: String          // use providerId as id
    let provider: String    // "mastodon" | "bluesky" | "linkedin"
    let providerId: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case provider, displayName
        case providerId = "providerId"
    }

    var id: String { providerId }
}
```

Note: `id` and `providerId` are the same value — use a computed `id` on the `Identifiable` conformance rather than a stored property to avoid duplication:

```swift
struct SocialIdentity: Codable {
    let provider: String
    let providerId: String
    let displayName: String?
}
extension SocialIdentity: Identifiable { var id: String { providerId } }
```

### 2. `APIClient.swift` — add `userIdentities()`

```swift
func userIdentities() async throws -> [SocialIdentity] {
    struct R: Decodable { let identities: [SocialIdentity] }
    return (try await get("/api/user/identities") as R).identities
}
```

**Add cross-post fields to `postMessage`:**

Add parameters to `postMessage(...)`:
```swift
mastodonProviderIds: [String]? = nil,
crossPostToBluesky: Bool? = nil,
crossPostToLinkedIn: Bool? = nil
```

Add to `CreateMessageBody`:
```swift
let mastodonProviderIds: [String]?
let crossPostToBluesky: Bool?
let crossPostToLinkedIn: Bool?
```

Pass them through in `postMessage` body construction.

### 3. `ComposeView.swift` — wire identities into advanced bar

**New state vars:**
```swift
@State private var identities: [SocialIdentity] = []
@State private var crossPostMastodon: Bool = false
@State private var crossPostBluesky: Bool = false
@State private var crossPostLinkedIn: Bool = false
```

**Load identities** in `.onAppear` (alongside `applyUserDefaults()`):
```swift
Task {
    if let loaded = try? await APIClient.shared.userIdentities() {
        identities = loaded
    }
}
```

**Replace the three disabled stub buttons** with conditional toggles — only show a platform button if the user has a connected identity for that provider:

```swift
// Mastodon
if identities.contains(where: { $0.provider == "mastodon" }) {
    Button {
        crossPostMastodon.toggle()
    } label: {
        Text("M")
            .font(.caption.weight(.semibold))
            .foregroundStyle(crossPostMastodon ? Color.accentColor : Color.secondary)
            .frame(width: 22, height: 22)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(crossPostMastodon ? "Remove Mastodon cross-post" : "Cross-post to Mastodon")
}

// Bluesky
if identities.contains(where: { $0.provider == "bluesky" }) {
    Button {
        crossPostBluesky.toggle()
    } label: {
        Text("BS")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(crossPostBluesky ? Color.accentColor : Color.secondary)
            .frame(width: 22, height: 22)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(crossPostBluesky ? "Remove Bluesky cross-post" : "Cross-post to Bluesky")
}

// LinkedIn
if identities.contains(where: { $0.provider == "linkedin" }) {
    Button {
        crossPostLinkedIn.toggle()
    } label: {
        Text("in")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(crossPostLinkedIn ? Color.accentColor : Color.secondary)
            .frame(width: 22, height: 22)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(crossPostLinkedIn ? "Remove LinkedIn cross-post" : "Cross-post to LinkedIn")
}
```

If the user has NO connected identities for a platform, the button simply does not render (no disabled stubs).

**Wire cross-post values into `postMessage()`:**

Collect Mastodon provider IDs from identities:
```swift
let mastodonIds = crossPostMastodon
    ? identities.filter { $0.provider == "mastodon" }.map { $0.providerId }
    : nil
```

Pass to `APIClient.shared.postMessage(...)`:
```swift
mastodonProviderIds: mastodonIds,
crossPostToBluesky: crossPostBluesky ? true : nil,
crossPostToLinkedIn: crossPostLinkedIn ? true : nil
```

**Reset cross-post toggles** in the success alert OK handler.

## Acceptance Criteria
- If the user has no connected social accounts, the M/BS/in buttons do not appear (clean UI).
- If a platform is connected, its button appears in the advanced bar and toggles accent/secondary color.
- A post with a cross-post toggle active sends the correct fields in the request body.
- `userIdentities()` silently swallows non-401 errors (e.g. 404 if server doesn't support endpoint) — identities defaults to `[]`.
- Build succeeds.
