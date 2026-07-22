# API Docs ↔ Implementation Gaps — for the interlinedlist.com site / API team

**Prepared:** 2026-07-18
**Updated:** 2026-07-22 — added the list-schema create contract (F15/F16); see the
Addendum in §9. Most of that item is **already resolved** on your side.
**By:** the InterlinedList **iOS** client team
**Sources:**
1. The shipped iOS client's `APIClient.swift` — a production HTTP client that
   actually calls these endpoints.
2. The public docs at `https://interlinedlist.com/help/api/*` (all detail pages
   read verbatim on 2026-07-18).
3. **Live read-only probes** against production on 2026-07-18 using the
   `messenger@interlinedlist.com` test account (a **subscriber**). Probes were
   GETs, `OPTIONS` (for `Allow`-header verb detection), and the login POST only —
   **no data was mutated.**

> Because we ran live probes, most items below are now **CONFIRMED** rather than
> "reconcile." Each finding is tagged with who owns the fix:
> **[DOC]** docs are wrong/incomplete · **[BACKEND]** the API blocks the mobile
> client (Bearer rejected) · **[iOS]** the client is wrong (we'll fix it; listed
> so you know your docs are right) · **[VERIFY]** still needs a write-test or a
> non-subscriber account.

---

## 0. The one systemic finding

**Several whole feature areas reject Bearer tokens and only accept a session
cookie.** The iOS app is **Bearer-only** (it has no cookie jar), so these
features are simply unreachable from mobile. Confirmed live (401 with a valid
Bearer) and/or stated in your own docs:

| Area | Endpoint(s) | Bearer? | Consequence for iOS |
|---|---|---|---|
| CSV Exports | `GET /api/exports/*` | ❌ 401 (confirmed live) | Export feature is **dead** in the shipped app |
| GitHub | `GET/POST/PATCH /api/github/*` | ❌ (docs: "not accepted") | GitHub-backed lists & issues **cannot be built** for iOS |
| LinkedIn targets | `GET/PUT /api/linkedin/posting-targets` | ❌ 401 (confirmed live) | LinkedIn org/target picker **cannot be built** for iOS |

**The single highest-value thing you can do for mobile parity is add Bearer-token
support to these endpoints** (see Prompt A). Everything else below is smaller.

---

## 1. Findings at a glance (all CONFIRMED unless noted)

| # | Owner | Finding | Evidence |
|---|---|---|---|
| F1 | **BACKEND** | `GET /api/exports/*` rejects Bearer (session-only) | Live: 401 w/ valid Bearer + no-auth |
| F2 | **BACKEND** | `GET/PUT /api/linkedin/posting-targets` rejects Bearer | Live: 401; docs say "Auth: Session" |
| F3 | **BACKEND** | All `/api/github/*` reject Bearer | Docs: "Bearer tokens are not accepted" |
| F4 | **DOC** | Messages page **auth column is unreliable** — `/api/messages/:id/replies` is marked "Session" but returns **200 with no auth at all** | Live: 200 Bearer + 200 no-auth |
| F5 | **DOC** | **No Moderation docs section exists**, but report/block/mute are live | Live: `GET /api/user/blocks` & `/mutes` → 200 (Bearer) |
| F6 | **DOC** | `POST /api/user/organizations` is documented as "Create new organization" but the client (and, we believe, the product) uses it to **join** an existing org | Client sends `{organizationId}`; docs say "create" |
| F7 | **DOC** | Document **folder path-scoping** has no warning — root routes silently ignore folders | Docs omit the caveat; causes silent data-loss |
| F8 | **iOS** | Client uses `POST /api/user/update`; server allows **only `PATCH`** → profile/settings/avatar-URL writes 405 | Live OPTIONS `Allow: OPTIONS, PATCH` |
| F9 | **iOS** | Client uses `PUT /api/messages/:id` to edit; server allows **`PATCH`, not `PUT`** → edit 405 | Live OPTIONS `Allow: DELETE, GET, HEAD, OPTIONS, PATCH` |
| F10 | **iOS** | Client uses `PUT /api/notifications/:id/read`; server allows **only `PATCH`** → mark-read 405 | Live OPTIONS `Allow: OPTIONS, PATCH` |
| F11 | **iOS** | Client sends Bearer to exports (see F1) → export is dead | Live 401 |
| F12 | **VERIFY** | Push body field: docs say **`deviceToken`**, client sends **`token`** → likely silent push failure | Not write-tested; verb/path confirmed correct |
| F13 | **VERIFY** | `POST /api/documents` documented **Subscriber-only**; iOS assumes documents are **free** | Test account is a subscriber; couldn't observe free-user path |
| F14 | **DOC** | `crossPostResults[].platform` can be omitted (crashed a strict client decoder) | Client patched it to optional |
| F15 | **iOS** *(fixed 2026-07-22)* | `POST /api/lists` client sent `schema` as a DSL **string** and read the created list from a `list` key; server wants a DSL **object** and returns it under **`data`** | Live 400 "Invalid Schema: DSL must be an object"; backend `validateDSLSchema` + route return `{message, data}` |
| F16 | **DOC** *(resolved 2026-07-22)* | Docs previously showed `POST /api/lists` `"schema": "string"` — the exact form the server rejects; now corrected to the object form. Residual: canonical ref still omits the response-body envelope | `/help/api/lists`, `/help/api/lists-dsl`, `api-reference.md:2709` now object; response body still status-codes only |

---

## 2. [BACKEND] Endpoints that reject Bearer and block the mobile client

### F1 — CSV Exports are session-only (confirmed)
```
GET /api/exports/messages   [Bearer]  -> 401 {"error":"Unauthorized"}
GET /api/exports/lists      [Bearer]  -> 401
GET /api/exports/follows    [Bearer]  -> 401
GET /api/exports/list-data-rows [Bearer] -> 401
GET /api/exports/messages   [no auth] -> 401
```
Your docs correctly state exports don't accept Bearer — so **the docs are right
and the iOS export feature is broken** (it sends Bearer and always 401s). To make
export work on mobile, **add Bearer support to `/api/exports/*`**. (Separately,
your docs list a `list-data-rows` export the client doesn't know about — we may
add it once auth works.)

### F2 — LinkedIn posting-targets are session-only (confirmed)
```
GET /api/linkedin/posting-targets [Bearer] -> 401
```
Docs (`/help/api/linkedin-integration`) confirm "Auth: Session" for
`/api/linkedin/targets`, `/api/linkedin/posting-targets` (GET+PUT), and
`/api/linkedin/sync-pages`. The composer's `linkedInTargets` field on
`POST /api/messages` already works, but iOS **can't fetch the target list** to
populate a picker. **Add Bearer support to the LinkedIn targets endpoints** and
the iOS target picker becomes buildable. (Thanks for documenting the response
shape — `{targets:[{kind, label, pageId|personalPageId, linkedInPageId,
enabled}], orgScopeMissing}` — and the `pageId`/`personalPageId` → `linkedInTargets`
mapping. That's exactly what we need.)

### F3 — GitHub integration is session-only
Docs (`/help/api/github-integration`): every `/api/github/*` endpoint requires
"a session cookie (Bearer tokens are not accepted)" plus a linked GitHub
identity, and these "power features like GitHub-backed lists." GitHub-backed
lists are a headline web feature iOS can't reach at all. **Add Bearer support to
`/api/github/*`** to unblock a native GitHub-backed-lists experience.

---

## 3. [DOC] Documentation fixes

### F4 — Audit the Messages page auth column (it's demonstrably wrong)
`/help/api/messages` marks `GET /api/messages/:id/replies`, `POST /:id/dig`,
`DELETE /:id/dig`, and `PATCH /:id` as **Session**. But live:
```
GET /api/messages/:id/replies [Bearer]  -> 200
GET /api/messages/:id/replies [no auth] -> 200   (it's effectively public for public messages)
```
So the "Session" label is wrong for replies. Please re-audit the auth column for
the whole Messages page against the actual middleware — where Bearer works, say
"Session or Bearer"; where an endpoint is public, say "Public." (`dig`/`undig`
are writes we didn't probe, but given `replies` was mislabeled, treat the whole
column as suspect.)

### F5 — Add a Moderation section (endpoints exist and are live)
There is **no `/help/api/moderation` page** and no moderation section in the
index. These are live and Bearer-accepted (Apple requires them for our app):
```
GET /api/user/blocks?limit=1 [Bearer] -> 200 {"blockedUsers":[],"pagination":{...}}
GET /api/user/mutes?limit=1  [Bearer] -> 200 {"mutedUsers":[],"pagination":{...}}
```
The client also uses (writes, not probed): `POST /api/messages/:id/report`,
`POST /api/users/:id/report`, `POST|DELETE /api/users/:id/block`,
`POST|DELETE /api/users/:id/mute`. Please document all of them (paths, bodies —
reports take `{reason, detail?}` — auth, response shapes).

### F6 — Clarify `POST /api/user/organizations`: create vs. join
`/help/api/users-and-profile` documents `POST /api/user/organizations` as
**"Create new organization."** The iOS client calls it with `{ organizationId }`
to **join an existing org** (it creates orgs via `POST /api/organizations`).
Please clarify the real semantics: does `POST /api/user/organizations` create,
join, or branch on the body? If join is a different route, tell us. Also
`GET /api/user/organizations` (list my orgs) — confirmed live 200 — is
documented here now; good.

### F7 — Add a folder path-scoping warning to Documents / Document Folders
The Document Folders page documents `POST`/`GET
/api/documents/folders/:id/documents`, but neither page warns that:
- `GET /api/documents` returns **only root docs** and **ignores `?folderId`**.
- `POST /api/documents` **always creates at root** (no `folderId` field).
- Only `PATCH /api/documents/:id` accepts `folderId` (to move).

Using the root routes for folder content **silently drops docs to root**. A
prominent callout on both pages would save every future integrator this bug.

### F14 — Document the `crossPostResults` shape (mark `platform` optional)
On `POST /api/messages` with cross-posting, response `crossPostResults[]` entries
sometimes **omit `platform`** (observed with Bluesky), which crashed a strict
decoder. Please document the shape and which fields are optional, or always emit
`platform`.

---

## 4. [iOS] Verb/auth mismatches we will fix (your docs are right — listed for awareness)

These are **client bugs** confirmed via live `OPTIONS` `Allow` headers. We're
fixing them on our side. They're here so you know (a) your docs are correct and
(b) *if* you'd rather accept the client's verb too, that's an option.

| Endpoint | Server allows | Client sends | Result | Our fix |
|---|---|---|---|---|
| `/api/user/update` | `OPTIONS, PATCH` | `POST` | 405 → profile/settings/avatar-URL writes fail | switch to `PATCH` |
| `/api/messages/:id` (edit) | `…, PATCH` (no `PUT`) | `PUT` | 405 → message edit fails | switch to `PATCH` |
| `/api/notifications/:id/read` | `OPTIONS, PATCH` | `PUT` | 405 → mark-read fails | switch to `PATCH` |
| `/api/exports/*` | session cookie only | Bearer | 401 → export dead | needs your F1 fix |

> If you'd like to reduce client breakage generally, accepting **both** `POST`
> and `PATCH` on `/api/user/update`, and **both** `PUT` and `PATCH` on the edit
> routes, would make the API more forgiving — but it's not required; we'll align
> the client regardless.

---

## 5. [VERIFY] Two items we couldn't confirm read-only

### F12 — Push registration body field (`token` vs `deviceToken`)
Path and verb are correct (`POST /api/push/register`, `DELETE
/api/push/unregister` — confirmed via `Allow`). But your docs show the body field
as **`deviceToken`** (plus `platform`, optional `appId`) while the client sends
**`token`**. If the handler reads `deviceToken`, iOS device tokens are being
**silently dropped** (no error, no push). We didn't write-test this. Please
either confirm the handler field name (we'll rename the client) or accept `token`
as an alias. This is the highest-impact silent-failure candidate remaining.

### F13 — Is document creation subscriber-only or free?
`/help/api/documents` marks `POST /api/documents` (and image upload, and
template creation) **Subscriber only**. The iOS product direction assumes
**documents are free**. Our test account is a subscriber, so we couldn't observe
the free-user path. Please confirm the real gate. If creation is subscriber-only,
free iOS users silently can't create docs and we must hide that UI; if it's free,
drop the "Subscriber only" label.

---

## 6. Confirmed-CORRECT (please do NOT "fix" these)

Live-verified that docs and client already agree — flagged so nothing here gets
changed by mistake:
- `POST /api/user/delete` (account deletion) — `Allow: OPTIONS, POST` ✓
- `POST /api/user/avatar/from-url`, `POST /api/user/avatar/upload` ✓
- `POST /api/notifications/mark-all-read` ✓; `GET /api/notifications` requires
  `scope=tray` (400 without) ✓
- `GET /api/user/notification-preferences` + `PATCH` ✓
- `GET /api/user/identities`, provider `status` for LinkedIn/Twitter only ✓
- Public-browse namespace split is **real and load-bearing** (do not "normalize"):
  - `GET /api/user/:username/messages` (singular `user`) → 200; the plural form → **404**
  - `GET /api/users/:username/lists` / `/lists/:id/data` / `/documents` (plural `users`) → 200; the singular form → **404**
  - Recommend documenting this split explicitly — it's a footgun even though it's intentional.
- `GET /api/documents/templates`, `GET /api/documents/sync` — live 200 over Bearer ✓

---

## 7. Ready-to-paste prompts for the site/API team's Claude

### Prompt A — Add Bearer support to the session-only feature areas (highest value)
> Our iOS app authenticates with Bearer tokens only (no session cookie). Live
> probing on 2026-07-18 confirmed these return 401 to a valid Bearer:
> `GET /api/exports/{messages,lists,follows,list-data-rows}` and
> `GET /api/linkedin/posting-targets`; and the docs state `/api/github/*` also
> reject Bearer. In the API, extend the auth middleware for `/api/exports/*`,
> `/api/linkedin/*`, and `/api/github/*` to accept `Authorization: Bearer <token>`
> the same way `/api/messages` and `/api/user` already do. If any must stay
> session-only for a security reason, document that explicitly and tell us so we
> can drop those features from mobile. Then update each page's Auth column.

### Prompt B — Fix the Messages auth column and add a Moderation section
> 1. On `/help/api/messages`, the Auth column is wrong: `GET /api/messages/:id/replies`
>    is marked "Session" but returns 200 with a Bearer token AND with no auth at
>    all. Re-audit every row against the actual middleware and correct the column
>    ("Session or Bearer" / "Public" as appropriate), especially `replies`, `dig`,
>    `undig`, and `PATCH /:id`.
> 2. Add a **Moderation** docs page. These are live: `GET /api/user/blocks`,
>    `GET /api/user/mutes`, `POST /api/messages/:id/report`,
>    `POST /api/users/:id/report`, `POST|DELETE /api/users/:id/block`,
>    `POST|DELETE /api/users/:id/mute`. Document paths, bodies (reports take
>    `{reason, detail?}`), auth, and response shapes, and link it from the index.

### Prompt C — Clarify org-join and add the doc-folder warning
> 1. `/help/api/users-and-profile` documents `POST /api/user/organizations` as
>    "Create new organization," but our client posts `{ organizationId }` to it to
>    JOIN an existing org (it creates via `POST /api/organizations`). Clarify the
>    real behavior of `POST /api/user/organizations` (create vs join vs
>    body-dependent) and document the canonical join route.
> 2. On `/help/api/documents` and `/help/api/document-folders`, add a prominent
>    warning: `GET /api/documents` ignores `?folderId` and `POST /api/documents`
>    always writes to root; to create/list inside a folder you MUST use
>    `/api/documents/folders/:id/documents`. Using the root routes silently drops
>    documents to root.

### Prompt D — Confirm two ambiguous contracts
> 1. Push: does the `POST /api/push/register` / `DELETE /api/push/unregister`
>    handler read the body field `deviceToken` or `token`? Our iOS client sends
>    `token`; your docs show `deviceToken`. If it reads `deviceToken`, our tokens
>    are silently dropped — either accept `token` as an alias or tell us to rename.
> 2. Documents: is `POST /api/documents` truly subscriber-only (as the docs say)
>    or free? It changes whether our iOS app must hide document creation from
>    free users. Confirm against the handler.

### Prompt E — Document the crossPostResults response shape
> On `POST /api/messages` with cross-posting, document the exact shape of
> `crossPostResults[]` and mark optional fields — in particular `platform` is
> sometimes omitted (observed for Bluesky), which crashed a strict client
> decoder. Either always include `platform` or document it as optional.

---

## 8. Coverage & method notes

**Docs pages read verbatim (2026-07-18):** `/help/api` and all detail pages —
`authentication`, `users-and-profile`, `public-profiles`, `messages`,
`following`, `lists`, `list-folders`, `documents`, `document-folders`,
`notifications`, `push-notifications`, `exports`, `organizations`,
`github-integration`, `linkedin-integration`, `utility-endpoints`,
`administration`. (There is **no** `moderation` page — that's finding F5.)

**Re-review 2026-07-22 (targeted):** `/help/api`, `/help/api/lists`, the new
`/help/api/lists-dsl` page, and `docs/api-reference.md` §`POST /api/lists`, prompted
by a live `400 "Invalid Schema: DSL must be an object"`. See §9.

**Live probe (read-only) on 2026-07-18, account `messenger` (subscriber):**
login (POST sync-token), ~30 GETs, and `OPTIONS` verb-detection on 15 routes.
No writes were performed.

**Not tested (would require writes or a different account):** push body-field
behavior (F12), the create-vs-join semantics of `POST /api/user/organizations`
(F6), the free-user document-creation gate (F13), and `dig`/`undig` auth (F4).
We're happy to run authorized write-tests for any of these if useful.

**Recommendation:** diff this report against your OpenAPI/route table. The
client-contract items (Section 4) and the Bearer-rejection items (Section 2) are
where a real, shipped consumer already diverges from the platform today.

---

## 9. Addendum — 2026-07-22: the `POST /api/lists` schema contract

A real user hit **`400 "Invalid Schema: DSL must be an object"`** creating a list.
Root-causing it surfaced one client bug (F15, now fixed) and one doc problem that
**you've already largely fixed** while we were investigating (F16). Recording both
so the report stays accurate and closes the loop.

### F15 — [iOS, FIXED] client sent a DSL *string* and read the wrong response key
The shipped client built `schema` as the legacy comma-separated DSL **string**
(`"Title:text, Author:text"`) and decoded the created list from a **`list`** key.
The server (`validateDSLSchema` in `lib/lists/dsl-parser.ts`) requires `schema` to
be a DSL **object** and rejects any non-object with *"DSL must be an object"*; the
route returns the created list under **`data`** (`{ "message": …, "data": { … } }`),
not `list`. We fixed the client on 2026-07-22 to send the object and decode `data`:

```jsonc
// POST /api/lists  — request body the client now sends
{
  "title": "Books to Read",
  "isPublic": true,
  "schema": {                      // object, NOT "Title:text, Author:text"
    "name": "Books to Read",
    "fields": [
      { "key": "title",  "type": "text",   "label": "Title",  "displayOrder": 0,
        "required": false, "visible": true }
    ]
  }
}
// 201 response — list is under `data`
{ "message": "List created successfully", "data": { "id": "lst_…", "properties": [ … ] } }
```

This one is on us — listed so you know your (corrected) docs are right.

### F16 — [DOC, RESOLVED] the docs used to show the string form; residual response gap
As of our 2026-07-18 read, both `/help/api/lists` and the canonical
`docs/api-reference.md` documented `POST /api/lists` with **`"schema": "string"`**
and the old `"Name:type, Name:type"` example — i.e. the docs described *exactly the
request the server now rejects*. Any integrator following them would have hit F15.

Re-checked 2026-07-22: **this is fixed.** `/help/api/lists`, the new dedicated
**`/help/api/lists-dsl`** reference (nice addition — types + object shape are clear),
and `docs/api-reference.md:2709` all now show the DSL **object**. Thank you.

**Two small residuals worth closing:**
1. **Response body isn't documented.** The `POST /api/lists` section of the canonical
   `docs/api-reference.md` still lists only status codes (201/400/401/403) with no
   response-body example, so the `{ message, data: { … } }` envelope (the second half
   of our client bug) is undocumented. A one-line example would prevent the next
   client from decoding the wrong key.
2. **Subscriber gate.** The route is `[Subscriber]`-only and returns
   `403 "Subscribe to create lists."` for non-subscribers (same family as F13). This
   is documented in `api-reference.md`; we're just flagging it as a **[VERIFY, iOS]**
   to confirm our app surfaces that 403 gracefully rather than as a generic failure.
