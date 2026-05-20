#!/usr/bin/env python3
"""
InterlinedList API end-to-end test.

Tests every auth variant the iOS app uses, then checks each endpoint
that has been reported as returning 401.

Usage:
    python3 scripts/test_api.py <email> <password>

Environment variables (alternative to positional args):
    IL_EMAIL    IL_PASSWORD
"""

import json
import os
import sys
import urllib.error
import urllib.request
from http.cookiejar import CookieJar

BASE = "https://interlinedlist.com"
PASS = "\033[32m✓\033[0m"
FAIL = "\033[31m✗\033[0m"


# ---------------------------------------------------------------------------
# Minimal HTTP client that tracks cookies like URLSession.shared does
# ---------------------------------------------------------------------------

class Session:
    def __init__(self):
        self.jar = CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar)
        )
        self.token: str | None = None

    def request(self, method: str, path: str, body: dict | None = None,
                bearer: bool = True, extra_headers: dict | None = None) -> tuple[int, dict, bytes]:
        url = BASE + path
        data = json.dumps(body).encode() if body else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Accept", "application/json")
        if data:
            req.add_header("Content-Type", "application/json")
        if bearer and self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        for k, v in (extra_headers or {}).items():
            req.add_header(k, v)
        try:
            with self.opener.open(req) as resp:
                raw = resp.read()
                return resp.status, dict(resp.headers), raw
        except urllib.error.HTTPError as e:
            raw = e.read()
            return e.code, dict(e.headers), raw

    def cookies(self) -> dict:
        return {c.name: c.value for c in self.jar}


def check(label: str, status: int, raw: bytes, expect: int = 200) -> dict | None:
    ok = status == expect
    symbol = PASS if ok else FAIL
    try:
        body = json.loads(raw)
    except Exception:
        body = None
    snippet = (body or raw[:200]).get("error", "") if isinstance(body, dict) else ""
    print(f"  {symbol} {label}: HTTP {status}" + (f" — {snippet}" if snippet else ""))
    return body if ok else None


# ---------------------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------------------

def run(email: str, password: str):
    s = Session()

    print("\n── 1. Authentication ──────────────────────────────────────────")
    status, headers, raw = s.request(
        "POST", "/api/auth/sync-token",
        body={"email": email, "password": password},
        bearer=False,
    )
    body = check("POST /api/auth/sync-token", status, raw)
    if body is None:
        print("  Cannot continue without a token.")
        sys.exit(1)

    s.token = body.get("token", "")
    print(f"  token  : {s.token[:24]}…")
    print(f"  cookies: {list(s.cookies().keys()) or '(none)'}")

    print("\n── 2. /api/user — should always work with Bearer ─────────────")
    status, _, raw = s.request("GET", "/api/user")
    user = check("GET /api/user (Bearer)", status, raw)
    if user:
        u = user.get("user", user)
        print(f"  logged in as @{u.get('username','?')}")

    print("\n── 3. /api/lists — the failing endpoint ──────────────────────")

    # 3a: Bearer only (what the app sends)
    status, _, raw = s.request("GET", "/api/lists")
    check("GET /api/lists (Bearer only)", status, raw)

    # 3b: Cookies only (no Bearer header)
    status, _, raw = s.request("GET", "/api/lists", bearer=False)
    body = check("GET /api/lists (cookies only)", status, raw)
    if body:
        print(f"  → {len(body.get('lists', []))} lists returned")

    # 3c: Bearer + cookies (the real app scenario — URLSession.shared carries both)
    # This is the same as 3a since the session already has cookies; just confirm.
    print("  (note: the app uses URLSession.shared which sends BOTH Bearer + any cookies)")

    print("\n── 4. Inspect what the login response sets ────────────────────")
    print(f"  Set-Cookie names after login : {list(s.cookies().keys()) or '(none set)'}")
    print("  If empty → server does NOT set a session cookie on sync-token.")
    print("  That means cookie-only endpoints will always 401 from the mobile app.")

    print("\n── 5. Other guarded endpoints ────────────────────────────────")
    for path in ["/api/folders", "/api/documents", "/api/notifications?scope=tray"]:
        status, _, raw = s.request("GET", path)
        check(f"GET {path} (Bearer)", status, raw)

    print()


# ---------------------------------------------------------------------------

if __name__ == "__main__":
    email = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("IL_EMAIL", "")
    password = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("IL_PASSWORD", "")
    if not email or not password:
        print(f"Usage: python3 {sys.argv[0]} <email> <password>")
        print("   or: IL_EMAIL=x IL_PASSWORD=y python3 scripts/test_api.py")
        sys.exit(1)
    run(email, password)
