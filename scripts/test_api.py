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

    print("\n── GET /api/folders (structure) ──────────────────────────────")
    status, _, raw = s.request("GET", "/api/folders")
    body = check("GET /api/folders (Bearer)", status, raw)
    if body is not None:
        if not isinstance(body, dict) or "folders" not in body:
            print(f"  {FAIL} FAIL: response is missing top-level \"folders\" key")
        else:
            folders = body["folders"]
            if not isinstance(folders, list):
                print(f"  {FAIL} FAIL: \"folders\" value is not a list (got {type(folders).__name__})")
            else:
                print(f"  folders count: {len(folders)}")
                for folder in folders[:3]:
                    fid = folder.get("id", "<missing>")
                    fname = folder.get("name", "<missing>")
                    print(f"    id={fid!r}  name={fname!r}")
                for i, folder in enumerate(folders):
                    if not isinstance(folder.get("id"), str):
                        print(f"  {FAIL} FAIL: folder[{i}] \"id\" is not a string (got {type(folder.get('id')).__name__})")
                    if not isinstance(folder.get("name"), str):
                        print(f"  {FAIL} FAIL: folder[{i}] \"name\" is not a string (got {type(folder.get('name')).__name__})")

    print("\n── POST /api/folders (create) ───────────────────────────────")
    folder_name = "E2E-Test-Folder"
    status, _, raw = s.request("POST", "/api/folders", body={"name": folder_name})
    body = check("POST /api/folders", status, raw, expect=201)
    folder_id = None
    if body is not None:
        folder = body.get("folder", {})
        folder_id = folder.get("id")
        returned_name = folder.get("name")
        if returned_name == folder_name:
            print(f"  {PASS} name matches: {returned_name!r}")
        else:
            print(f"  {FAIL} name mismatch: sent {folder_name!r}, got {returned_name!r}")
        print(f"  created folder id: {folder_id}")
        if folder_id:
            s.request("DELETE", f"/api/folders/{folder_id}")

    print("\n── GET /api/lists/search ────────────────────────────────────")
    status, _, raw = s.request("GET", "/api/lists/search?q=a&limit=5&offset=0")
    body = check("GET /api/lists/search?q=a&limit=5&offset=0 (Bearer)", status, raw)
    if body is not None:
        if not isinstance(body.get("lists"), list):
            print(f"  {FAIL} FAIL: response is missing top-level \"lists\" list")
        else:
            pagination = body.get("pagination")
            if not isinstance(pagination, dict):
                print(f"  {FAIL} FAIL: response is missing top-level \"pagination\" dict")
            else:
                for key in ("total", "hasMore"):
                    if key not in pagination:
                        print(f"  {FAIL} FAIL: \"pagination\" is missing \"{key}\" key")
                if "total" in pagination and "hasMore" in pagination:
                    print(f"  result count : {len(body['lists'])}")
                    print(f"  hasMore      : {pagination['hasMore']}")

    status, _, raw = s.request("GET", "/api/lists/search?q=")
    check("GET /api/lists/search?q= (empty query, any status)", status, raw,
          expect=status)

    print("\n── PATCH /api/documents/[id] (folderId) ────────────────────")
    status, _, raw = s.request("GET", "/api/documents")
    docs_body = check("GET /api/documents (Bearer)", status, raw)
    if docs_body is None or not docs_body.get("documents"):
        print("  (no documents found — skipping PATCH /api/documents/[id] tests)")
    else:
        doc = docs_body["documents"][0]
        doc_id = doc.get("id")
        doc_title = doc.get("title", "")
        orig_folder_id = doc.get("folderId") or None

        status, _, raw = s.request("GET", "/api/documents/folders")
        folders_body = check("GET /api/documents/folders (Bearer)", status, raw)
        doc_folders = (folders_body or {}).get("folders", [])
        target_folder_id = doc_folders[0]["id"] if doc_folders else None

        status, _, raw = s.request(
            "PATCH", f"/api/documents/{doc_id}",
            body={"title": doc_title, "folderId": target_folder_id},
        )
        patch_body = check(f"PATCH /api/documents/{doc_id} (folderId)", status, raw)
        if patch_body is not None:
            returned_folder_id = patch_body.get("document", {}).get("folderId") or None
            if returned_folder_id == target_folder_id:
                print(f"  {PASS} folderId matches: {returned_folder_id!r}")
            else:
                print(f"  {FAIL} folderId mismatch: sent {target_folder_id!r}, got {returned_folder_id!r}")

        s.request(
            "PATCH", f"/api/documents/{doc_id}",
            body={"title": doc_title, "folderId": orig_folder_id},
        )
        print(f"  (restored folderId to {orig_folder_id!r})")

    print("\n── PUT /api/lists/[id] (isPublic) ───────────────────────────")
    status, _, raw = s.request("GET", "/api/lists")
    lists_body = check("GET /api/lists (fetch for PUT test)", status, raw)
    if lists_body is None:
        print("  Skipping PUT test — could not fetch lists.")
    else:
        lists = lists_body.get("lists", [])
        if not lists:
            print("  Skipping PUT test — no lists found.")
        else:
            first = lists[0]
            list_id = first.get("id")
            orig_public = first.get("isPublic", False)
            print(f"  list id={list_id!r}  current isPublic={orig_public!r}")

            toggled = not orig_public
            status, _, raw = s.request(
                "PUT", f"/api/lists/{list_id}",
                body={"isPublic": toggled},
            )
            put_body = check(f"PUT /api/lists/{list_id} (isPublic={toggled})", status, raw)
            if put_body is not None:
                returned = put_body.get("list", {}).get("isPublic")
                if returned == toggled:
                    print(f"  {PASS} isPublic toggled correctly to {toggled!r}")
                else:
                    print(f"  {FAIL} FAIL: expected isPublic={toggled!r}, got {returned!r}")

            # Restore original value (best effort)
            s.request("PUT", f"/api/lists/{list_id}", body={"isPublic": orig_public})
            print(f"  (restored isPublic to {orig_public!r})")

    print("\n── GET /api/documents/search ───────────────────────────────")
    status, _, raw = s.request("GET", "/api/documents/search?q=a&limit=5&offset=0")
    body = check("GET /api/documents/search?q=a&limit=5&offset=0 (Bearer)", status, raw)
    if body is not None:
        if not isinstance(body.get("documents"), list):
            print(f"  {FAIL} FAIL: response is missing top-level \"documents\" list")
        else:
            pagination = body.get("pagination")
            if not isinstance(pagination, dict):
                print(f"  {FAIL} FAIL: response is missing top-level \"pagination\" dict")
            elif "total" not in pagination or "hasMore" not in pagination:
                print(f"  {FAIL} FAIL: \"pagination\" is missing \"total\" or \"hasMore\"")
            else:
                print(f"  result count : {len(body['documents'])}")
                print(f"  hasMore      : {pagination['hasMore']}")

    status, _, raw = s.request("GET", "/api/documents/search?q=zzzz_unlikely_match")
    body = check("GET /api/documents/search?q=zzzz_unlikely_match (Bearer)", status, raw)
    if body is not None:
        docs = body.get("documents")
        if not isinstance(docs, list):
            print(f"  {FAIL} FAIL: \"documents\" key missing or not a list")
        elif docs:
            print(f"  {FAIL} FAIL: expected empty list for unlikely query, got {len(docs)} item(s)")
        else:
            print(f"  {PASS} empty \"documents\" list as expected")

    print("\n── PUT /api/folders/[id] (rename) ───────────────────────────")
    status, _, raw = s.request("POST", "/api/folders", body={"name": "E2E-Rename-Source"})
    rename_body = check("POST /api/folders (setup)", status, raw, expect=201)
    if rename_body is None:
        print("  Skipping rename tests — folder creation failed.")
    else:
        rename_folder_id = (rename_body.get("folder") or {}).get("id", "")
        if not rename_folder_id:
            print(f"  {FAIL} Could not extract folder id from creation response — skipping.")
        else:
            status, _, raw = s.request(
                "PUT", f"/api/folders/{rename_folder_id}",
                body={"name": "E2E-Renamed"},
            )
            put_body = check(f"PUT /api/folders/{rename_folder_id}", status, raw)
            if put_body is not None:
                returned_name = (put_body.get("folder") or {}).get("name", "")
                name_ok = returned_name == "E2E-Renamed"
                symbol = PASS if name_ok else FAIL
                print(f"  {symbol} rename reflected in response: {returned_name!r}")

            # Cleanup — best effort, result ignored
            s.request("DELETE", f"/api/folders/{rename_folder_id}")

    print("\n── DELETE /api/folders/[id] ─────────────────────────────────")
    status, _, raw = s.request("POST", "/api/folders", body={"name": "E2E-To-Delete"})
    created = check("POST /api/folders (create temp folder)", status, raw, expect=201)
    if created is None:
        print(f"  {FAIL} SKIP: could not create temp folder — skipping DELETE tests")
    else:
        del_folder = created.get("folder") or {}
        del_folder_id = del_folder.get("id") or created.get("id")
        if not del_folder_id:
            print(f"  {FAIL} SKIP: could not extract folder id from creation response")
        else:
            print(f"  created folder id: {del_folder_id!r}")

            status, _, raw = s.request("DELETE", f"/api/folders/{del_folder_id}")
            del_body = check(f"DELETE /api/folders/{del_folder_id}", status, raw)
            if del_body is not None:
                if "message" in del_body:
                    msg_val = del_body["message"]
                    print(f"  {PASS} PASS: response contains \"message\" key: {msg_val!r}")
                else:
                    print(f"  {FAIL} FAIL: response missing \"message\" key (got keys: {list(del_body.keys())})")

                status, _, raw = s.request("GET", "/api/folders")
                verify = check("GET /api/folders (verify deletion)", status, raw)
                if verify is not None:
                    remaining_ids = [f.get("id") for f in verify.get("folders", [])]
                    if del_folder_id not in remaining_ids:
                        print(f"  {PASS} PASS: folder id {del_folder_id!r} is no longer in GET /api/folders")
                    else:
                        print(f"  {FAIL} FAIL: folder id {del_folder_id!r} still present after DELETE")


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
