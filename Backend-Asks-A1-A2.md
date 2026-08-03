# Backend Asks A1 & A2 — GitHub in-app linking + Universal Links

Hand-off spec for the two remaining backend/ops dependencies that unblock the last
of iOS↔web parity (see `the-gaps.md`). Both are **implemented** (backend PR + a
staged iOS branch); what remains is **deploy + Apple-portal provisioning** — the
steps I can't perform. Prepared 2026-08-03.

Facts used: iOS `DEVELOPMENT_TEAM = BJA9558E4B`, bundle `com.interlinedlist.app`,
custom scheme `interlinedlist://`, app host `interlinedlist.com`.

---

## A1 — GitHub in-app linking / sign-in (mobile OAuth handoff)

**Problem.** Every other OAuth provider (Twitter, Mastodon, Bluesky, LinkedIn)
completes on mobile because its `/authorize` stores the mobile `redirect_uri` and
its `/callback` mints a **sync token** and redirects to
`interlinedlist://oauth/callback?token=…`, which `ASWebAuthenticationSession`
captures. **GitHub alone** ignores `redirect_uri` and its callback always sets a
web session cookie + redirects to `/dashboard` — so iOS can neither sign in with
nor *link* GitHub. GitHub-backed lists (already Bearer-ready) are therefore
unreachable for iOS users who linked GitHub only on mobile.

**Fix (backend) — mirror the Twitter provider exactly.** Helpers already exist:
`isAllowedRedirectUri`/`isMobileRedirectUri` (`lib/auth/pkce.ts`),
`createSyncTokenForUser` (`lib/auth/sync-token.ts`), and `OAuthState.redirectUri`
(`lib/auth/oauth-state.ts`).

1. `app/api/auth/github/authorize/route.ts` — read `redirect_uri` from the query,
   validate with `isAllowedRedirectUri`, and pass it into `setOAuthStateCookie({ …,
   redirectUri })` (exactly as `twitter/authorize` does). GitHub's registered
   callback URL is unchanged — the mobile `redirectUri` lives only in our state.
2. `app/api/auth/github/callback/route.ts` — add a `buildSuccessResponse(userId,
   redirectUri?)` mirroring Twitter's:
   ```ts
   async function buildSuccessResponse(userId: string, redirectUri?: string) {
     if (redirectUri && isMobileRedirectUri(redirectUri)) {
       const token = await createSyncTokenForUser(userId, 'Mobile-GitHub');
       const url = new URL(redirectUri);
       url.searchParams.set('token', token);
       return NextResponse.redirect(url.toString());   // interlinedlist://oauth/callback?token=…
     }
     const response = NextResponse.redirect(`${APP_URL}/dashboard`); // unchanged web path
     response.cookies.set(SESSION_COOKIE_NAME, await createSession(userId), getSessionCookieOptions());
     return response;
   }
   ```
   Call it on **both** the link-success and sign-in-success branches
   (`oauthState.redirectUri` passed through), replacing the two hardcoded
   `/dashboard` redirects. The web flow (`redirectUri` absent) is byte-for-byte
   unchanged.

**Fix (iOS) — one line.** `OAuthCoordinator.supportsNativeAuth` currently returns
`self != .github`; change to `true`. `LoginView` and `LinkedIdentitiesView` filter
on this flag, so GitHub sign-in **and** linking light up automatically.

**Ordering (ops):** the iOS one-liner must ship **only after the backend change
deploys** — otherwise a GitHub button appears but 401s against prod. Staged on the
iOS branch below; hold its merge until deploy.

---

## A2 — Universal Links (`https://interlinedlist.com/…` opens the app)

**Problem.** iOS G10 already routes content permalinks (profiles `/user/*`,
messages `/message/*`, lists `/lists/*`, documents `/documents/*`) via `.onOpenURL`
+ the pure `AppDeepLink.parse`, and share actions emit `https://interlinedlist.com`
URLs. But an `https` tap only opens the app if (a) the site hosts a valid
**apple-app-site-association (AASA)** and (b) the app carries the **Associated
Domains** entitlement. The custom-scheme path works today; Universal Links do not.

**Fix (backend) — host the AASA, public + unredirected.**
- Serve `GET https://interlinedlist.com/.well-known/apple-app-site-association`
  (200, `Content-Type: application/json`, **no auth, no redirect**) with:
  ```json
  {
    "applinks": {
      "apps": [],
      "details": [
        {
          "appID": "BJA9558E4B.com.interlinedlist.app",
          "paths": [ "/user/*", "/message/*", "/lists/*", "/documents/*",
                     "NOT /api/*", "NOT /dashboard*", "NOT /login*", "NOT /help/*" ]
        }
      ]
    }
  }
  ```
- Implemented as a Next route handler at
  `app/.well-known/apple-app-site-association/route.ts` returning the JSON with the
  right content-type, **plus** a `middleware.ts` early-return so `/.well-known/*`
  bypasses auth/redirect (the current matcher would otherwise process it).

**Fix (iOS) — entitlement.** Add to `InterlinedList/InterlinedList.entitlements`:
```xml
<key>com.apple.developer.associated-domains</key>
<array><string>applinks:interlinedlist.com</string></array>
```
(kept alongside the existing `aps-environment`). No app code change — G10 already
parses https permalinks.

**Ordering (ops — human):** adding the entitlement makes **signed** device/
TestFlight/App-Store builds fail unless **Associated Domains is enabled for the App
ID in the Apple Developer portal and the provisioning profile is regenerated**.
(Simulator + the code-signing-disabled CI build are unaffected.) So: enable the
capability in the portal → regen profile → deploy the AASA → then merge the iOS
branch. Verify with Apple's CDN: `https://app-site-association.cdn-apple.com/a/v1/interlinedlist.com`.

---

## Status & what's left for a human

| Piece | Done | Human/ops step remaining |
|---|---|---|
| A1 backend (github authorize+callback) | ✅ PR | review + **deploy** |
| A1 iOS (`supportsNativeAuth` → true) | ✅ staged branch | merge **after** backend deploy |
| A2 backend (AASA route + middleware) | ✅ PR | review + **deploy**; verify via Apple CDN |
| A2 iOS (Associated Domains entitlement) | ✅ staged branch | enable **Associated Domains capability** in Apple portal + regen profile, then merge |

After these ops steps, the only remaining parity item is **G11** (live document
presence — optional). Everything else is a documented dead-end (multi-account,
tag discovery, realtime).
