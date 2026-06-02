# Plan 17 — Forgot Password & Email Verification

## Goal
1. Add a "Forgot password?" link to `LoginView` that initiates password reset.
2. Handle the case where the API returns 403 on post (unverified email) and prompt the user.

## Endpoints
- `POST /api/auth/forgot-password` — body: `{ email: String }` — no auth required.
  Expected response: `{ message: String }` (success) or error body.

## Files to Change

| File | Change |
|------|--------|
| `InterlinedList/Services/APIClient.swift` | Add `forgotPassword(email:)` |
| `InterlinedList/Views/LoginView.swift` | Add "Forgot password?" button + forgot-password sheet/alert |
| `InterlinedList/Views/ComposeView.swift` | Improve 403 error message to mention email verification |

## Step-by-Step

### 1. `APIClient.swift` — add `forgotPassword`

```swift
func forgotPassword(email: String) async throws -> String {
    struct Body: Encodable { let email: String }
    struct Response: Decodable { let message: String? }
    let r: Response = try await post("/api/auth/forgot-password",
                                      body: Body(email: email),
                                      authenticated: false)
    return r.message ?? "If an account exists for that email, a reset link has been sent."
}
```

### 2. `LoginView.swift` — add forgot-password flow

**New state vars:**
```swift
@State private var showForgotPassword = false
@State private var forgotEmail = ""
@State private var forgotIsLoading = false
@State private var forgotMessage: String?
@State private var forgotError: String?
```

**Add link below the "Create account" button** in the existing `Section`:

```swift
Button("Forgot password?") {
    forgotEmail = email   // pre-fill with whatever is already typed
    forgotMessage = nil
    forgotError = nil
    showForgotPassword = true
}
.frame(maxWidth: .infinity)
.foregroundStyle(.secondary)
.font(.footnote)
```

**Add sheet** attached to the `NavigationStack`:

```swift
.sheet(isPresented: $showForgotPassword) {
    NavigationStack {
        Form {
            Section {
                TextField("Email address", text: $forgotEmail)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
            } header: {
                Text("Enter your email to receive a password reset link.")
                    .font(.footnote)
                    .textCase(nil)
            }
            if let msg = forgotMessage {
                Section {
                    Text(msg).foregroundStyle(.green).font(.caption)
                }
            }
            if let err = forgotError {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            Section {
                Button {
                    Task { await sendForgotPassword() }
                } label: {
                    HStack {
                        if forgotIsLoading { ProgressView().frame(width: 20, height: 20) }
                        Text("Send Reset Link").frame(maxWidth: .infinity)
                    }
                }
                .disabled(forgotIsLoading || forgotEmail.isEmpty)
            }
        }
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { showForgotPassword = false }
            }
        }
    }
}
```

**Add `sendForgotPassword()` function:**

```swift
private func sendForgotPassword() async {
    forgotMessage = nil
    forgotError = nil
    forgotIsLoading = true
    defer { forgotIsLoading = false }
    do {
        let message = try await APIClient.shared.forgotPassword(email: forgotEmail)
        forgotMessage = message
    } catch APIError.server(let msg) {
        forgotError = msg
    } catch {
        forgotError = "Could not send reset email. Please try again."
    }
}
```

### 3. `ComposeView.swift` — improve 403 message

The current catch is:
```swift
} catch APIError.status(403) {
    errorMessage = "You may need to verify your email before posting."
```

This is already adequate. Optionally add a "Resend verification" note but that requires a separate endpoint — leave as-is for now unless that endpoint is available.

## Acceptance Criteria
- "Forgot password?" link appears below "Create account" on `LoginView`.
- Tapping it opens a sheet pre-filled with any email already typed in the login form.
- Submitting a valid email shows the server's success message ("reset link sent…").
- Server errors surface in red below the field.
- The sheet can be dismissed with Cancel at any time.
- Build succeeds.
