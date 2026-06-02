# Plan 12 — Avatar Upload via URL

## Goal
Add avatar-from-URL upload to `EditProfileView`. The API endpoint is `POST /api/user/avatar/from-url` with body `{ url: String }`. The endpoint is marked "Needs Bearer" in the docs but may already accept Bearer — test first.

## Files to Change

| File | Change |
|------|--------|
| `InterlinedList/Services/APIClient.swift` | Add `updateAvatarFromURL(url:)` method |
| `InterlinedList/Views/EditProfileView.swift` | Add avatar URL text field + save button |
| `InterlinedList/Models/User.swift` | No changes needed (`avatar: String?` already exists) |

## Step-by-Step

### 1. `APIClient.swift` — add method

Add after `updateProfile(...)` (around line 424):

```swift
func updateAvatarFromURL(_ avatarURL: String) async throws -> User {
    struct Body: Encodable { let url: String }
    struct Wrapped: Decodable { let user: User? }
    let wrapped: Wrapped = try await post("/api/user/avatar/from-url",
                                          body: Body(url: avatarURL))
    if let user = wrapped.user { return user }
    return try await currentUser()
}
```

Note: uses `post` (snake_case encoder). The body key is `url`, which is the same in both cases, so encoder strategy doesn't matter here.

### 2. `EditProfileView.swift` — add avatar section

Add a new `Section("Avatar")` above the `Section("Identity")` block:

```swift
Section("Avatar") {
    TextField("Avatar image URL", text: $avatarURL)
        .textContentType(.URL)
        .autocapitalization(.none)
        .keyboardType(.URL)
    Button {
        Task { await saveAvatar() }
    } label: {
        HStack {
            if isSavingAvatar { ProgressView().frame(width: 20, height: 20) }
            Text("Update Avatar").frame(maxWidth: .infinity)
        }
    }
    .disabled(isSavingAvatar || avatarURL.isEmpty)
}
```

New `@State` vars needed:
```swift
@State private var avatarURL: String = ""
@State private var isSavingAvatar = false
```

New `saveAvatar()` private function:
```swift
private func saveAvatar() async {
    errorMessage = nil
    isSavingAvatar = true
    defer { isSavingAvatar = false }
    guard let _ = URL(string: avatarURL), !avatarURL.isEmpty else {
        errorMessage = "Enter a valid image URL."
        return
    }
    do {
        let updated = try await APIClient.shared.updateAvatarFromURL(avatarURL)
        authState.updateUser(updated)
        avatarURL = ""
    } catch APIError.status(401) {
        authState.handleUnauthorized()
    } catch APIError.server(let msg) {
        errorMessage = msg
    } catch {
        errorMessage = "Could not update avatar. Please try again."
    }
}
```

### 3. Show current avatar in `EditProfileView`

At the top of `Section("Avatar")`, add a preview of the current avatar using `AsyncImage`:

```swift
if let avatarURLString = authState.user?.avatar,
   let url = URL(string: avatarURLString) {
    HStack {
        AsyncImage(url: url) { phase in
            if let img = phase.image {
                img.resizable().scaledToFill()
            } else {
                Image(systemName: "person.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        Text("Current avatar")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

### 4. Update `#Preview`

The existing preview in `EditProfileView.swift` already passes a `User` — no changes needed unless the new state initializers require it.

## Acceptance Criteria
- User can enter a URL in the Avatar section and tap "Update Avatar".
- On success, the current-avatar preview updates (requires `authState.updateUser` to trigger a re-render — it already does via `@Published var user`).
- On failure (bad URL format), a validation message shows before hitting the network.
- Build succeeds with zero new warnings.
