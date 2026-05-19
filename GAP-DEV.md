# GAP-DEV — Feature Gap Analysis & Implementation Plan

_Compared: website at `interlinedlist.com/help` and API at `interlinedlist.com/help/api` against current iOS app state. Date: 2026-05-18._

---

## Current iOS App Capability Summary

| Area | What exists |
|------|-------------|
| Auth | Login, register, logout, session restore via Keychain |
| Feed | Read-only paginated message feed, pull-to-refresh, load-more, reply sheet, delete own message, link/image/video previews |
| Compose | Post new message (text, visibility toggle, reply-to), stub buttons for advanced features |
| Lists | View own lists + folders in tree, view list items (read-only, checkmark display) |
| Documents | Placeholder screen only |
| Profile | Read-only display of own username, display name, avatar, bio, email, preferences |
| Navigation | Custom top-bar: Home · Lists · Documents · Profile |

---

## Gap Feature Punch List

Legend:
- **API ready** — endpoint confirmed, Bearer token auth expected to work (same pattern as existing calls)
- **Needs Bearer** — endpoint documented as Session-only; Bearer support must be added server-side before client can call it
- **Needs API work** — endpoint does not exist or requires significant server additions
- ✅ = Implemented in this session | 🔲 = Not yet implemented

---

### 1. Message Tags
**API ready** | `/api/messages?tag=<tag>` (GET) · `tags: [String]` field in POST body

- ✅ Add `tags: [String]?` to `Message` model
- ✅ Add `tags: [String]?` to `CreateMessageBody`
- ✅ Show tags as chips on `MessageRow`
- ✅ Add tag filter bar to `FeedView` (tap a tag chip to filter)
- ✅ Add tags text field to `ComposeView`

---

### 2. Message Editing
**API ready** | `PUT /api/messages/[id]` — body: `{ content, publiclyVisible }`

- ✅ Add `put<T,B>` helper to `APIClient`
- ✅ Add `editMessage(id:content:publiclyVisible:)` to `APIClient`
- ✅ Add `EditMessageView` sheet
- ✅ Show "Edit" action in `MessageRow` for own messages
- ✅ Update message in feed list after successful edit

---

### 3. Digs (Reactions / Likes)
**API ready** | `POST /api/messages/[id]/dig` · `DELETE /api/messages/[id]/dig`  
Response: `{ digCount: Int, dugByMe: Bool }`

- ✅ Add `digCount: Int?` and `dugByMe: Bool?` to `Message`
- ✅ Add `dig(messageId:)` and `undig(messageId:)` to `APIClient`
- ✅ Add dig count + toggle button to `MessageRow`
- ✅ Optimistic update via local `digStates` dictionary

---

### 4. Reply Thread View
**API ready** | `GET /api/messages/[id]/replies?limit=&offset=`

- ✅ Add `replies(messageId:limit:offset:)` to `APIClient`
- ✅ Create `MessageThreadView` (shows parent message + paginated replies)
- ✅ Wire "Reply" button in `MessageRow` to open thread view

---

### 5. Notifications
**Needs Bearer** (docs show Session-only — requires server-side Bearer support)  
`GET /api/notifications?scope=tray` → `{ unreadCount, items }`  
`PATCH /api/notifications/[id]/read` · `POST /api/notifications/mark-all-read`

- ✅ Add `AppNotification` model
- ✅ Add `notifications()`, `markRead(id:)`, `markAllRead()` to `APIClient`
- ✅ Create `NotificationsView`
- ✅ Add notifications tab/bell to `MainTabView` with unread badge

---

### 6. Follow / Unfollow Users
**Needs Bearer** (docs show Session-only)  
`POST /api/follow/[userId]` · `DELETE /api/follow/[userId]`  
`GET /api/follow/[userId]/status` · `GET /api/follow/[userId]/counts`  
`GET /api/follow/requests` · `POST /api/follow/[userId]/approve|reject`

- ✅ Add `FollowStatus`, `FollowCounts`, `FollowRequest` models
- ✅ Add `followUser`, `unfollowUser`, `followStatus`, `followCounts`, `followRequests`, `approveFollowRequest`, `rejectFollowRequest` to `APIClient`
- ✅ Follow button + follower/following counts on `UserProfileView`
- ✅ Make username tappable in `MessageRow` → opens `UserProfileView` sheet
- ✅ Add follow requests section to Profile tab (`FollowRequestsView`) and top-bar bell (`NotificationsView`)

---

### 7. View Public User Profiles & Messages
**API ready (no auth)** | `GET /api/user/[username]/messages` · `GET /api/users/[username]/lists`

- ✅ `UserProfileView` fetches public messages for any username
- ✅ Show public lists from a user's profile

---

### 8. Message Scheduling
**API ready** | `scheduledAt: String` (ISO 8601) in POST body · `GET /api/messages/scheduled`
Paid feature — requires subscription on account.

- ✅ Add date-time `DatePicker` to `ComposeView` advanced bar (calendar icon toggles inline picker)
- ✅ Wire `scheduledAt` into `CreateMessageBody` (ISO 8601 formatted)
- ✅ Add `ScheduledMessagesView` reachable from Feed toolbar (calendar icon)

---

### 9. List Management (Create / Edit / Delete)
**API ready** | `POST /api/lists` · `PATCH /api/lists/[id]` · `DELETE /api/lists/[id]`  
Body: `{ title, description, schema, isPublic, parentId? }`

- ✅ Add `createList`, `deleteList` to `APIClient`
- ✅ Add "+ New List" toolbar button to `ListsView`
- ✅ Create `CreateListView` sheet (name, description, public toggle)
- ✅ Add swipe-to-delete on list rows

---

### 10. List Item Management (Add / Check / Delete)
**API ready** | `POST /api/lists/[id]/data` · `PATCH /api/lists/[id]/data/[rowId]` · `DELETE /api/lists/[id]/data/[rowId]`  
Note: current app calls `/api/lists/[id]/items` (legacy); documented endpoint is `/api/lists/[id]/data`.

- ✅ Add `addListItem`, `deleteListItem` to `APIClient` (new `/data` endpoint)
- 🔲 Migrate list-items GET to `/api/lists/[id]/data` endpoint (legacy `/items` still works)
- ✅ Add `toggleListItem` (PATCH checked state) to `APIClient`
- ✅ Make checkmark in `ListItemRow` tappable (optimistic toggle with rollback)
- ✅ Add swipe-to-delete on item rows
- ✅ Add text-field row at bottom of `ListDetailView` to add new item

---

### 11. Documents
**API ready** | Full CRUD + folders. Session/Bearer both supported.  
`GET/POST /api/documents` · `PATCH/DELETE /api/documents/[id]`  
`GET/POST /api/documents/folders`

- ✅ Add `Document`, `DocumentFolder` models
- ✅ Add `documents()`, `createDocument()`, `updateDocument()`, `deleteDocument()`, `documentFolders()`, `createDocumentFolder()` to `APIClient`
- ✅ Replace `DocumentsPlaceholderView` with `DocumentsView`
- ✅ Folder tree navigation (root folders → subfolders → documents)
- ✅ `DocumentDetailView` with markdown rendering (`AttributedString(markdown:)`)
- ✅ Create/edit document sheets; swipe-to-delete on document rows

---

### 12. Profile Editing
**Needs Bearer** | `POST /api/user/update` — body: `{ displayName, bio, defaultVisibility }`  
`POST /api/user/avatar/from-url` — body: `{ url }`

- ✅ Add `updateProfile` to `APIClient`
- ✅ Add `EditProfileView` sheet to `ProfileView` (display name, bio, default visibility)
- 🔲 Avatar upload via URL (`POST /api/user/avatar/from-url`)

---

### 13. Organizations
**Needs Bearer** | Full CRUD + member management.
- 🔲 Add `Organization`, `OrganizationMember` models
- 🔲 Add org API methods to `APIClient`
- 🔲 Add Organizations section (tab or reachable from Profile)
- 🔲 Org detail view with member list

---

### 14. Image / Video Attachment
**API ready** | `POST /api/messages/images/upload` (multipart/form-data) · `POST /api/messages/videos/upload`  
Paid feature.

- ✅ `PhotosPicker` integration in `ComposeView` (advanced bar photo button)
- ✅ `uploadImage(data:mimeType:)` multipart helper in `APIClient`
- ✅ Wire `imageUrls` into `CreateMessageBody`; uploaded image thumbnail shown in compose
- 🔲 Video upload (`POST /api/messages/videos/upload`)

---

### 15. Cross-Posting to Mastodon / Bluesky / LinkedIn
**Needs API work** | Requires connected-account provider IDs from `GET /api/user/identities`.  
Fields: `mastodonProviderIds: [String]`, `crossPostToBluesky: Bool`, `crossPostToLinkedIn: Bool`
- 🔲 Add `GET /api/user/identities` to `APIClient`
- 🔲 Show connected platform toggles in `ComposeView` advanced bar (currently stubs)

---

### 16. Dashboard / My Messages View
**API ready** | `GET /api/messages?onlyMine=true`

- ✅ Add "My Posts" filter toggle to `FeedView`

---

### 17. Forgot Password & Email Verification
**Needs UI only** (web-redirect flow) | `POST /api/auth/forgot-password`
- 🔲 Add "Forgot password?" link to `LoginView` that opens Safari or posts email
- 🔲 Handle email-verification prompt when API returns 403 on post

---

### 18. Data Exports
**Needs Bearer** | `GET /api/exports/messages|lists|follows` — returns CSV.  
Low value on mobile; share sheet is reasonable output.
- 🔲 Add export actions to `ProfileView` (share CSV via `ShareLink`)

---

### 19. List Connections
**Needs Bearer** | `GET /api/lists/connections` · `POST /api/lists/connections` · `DELETE /api/lists/connections/[id]`
- 🔲 Add connections section to `ListDetailView`

---

## API Bearer Extension Requirements

The following endpoints are documented as Session-cookie only. The API server must add Bearer token acceptance to unlock them for the iOS app:

| Endpoint | Feature blocked |
|----------|----------------|
| `POST /api/user/update` | Profile editing (#12) |
| `POST /api/user/avatar/*` | Avatar upload (#12) |
| `POST/DELETE /api/follow/*` | Follow/unfollow (#6) |
| `GET /api/follow/requests` | Follow requests (#6) |
| `GET /api/notifications` | Notifications (#5) |
| `PATCH /api/notifications/*` | Mark notification read (#5) |
| `GET /api/organizations/*` | Organizations (#13) |
| `GET /api/exports/*` | Data exports (#18) |
| `GET/POST /api/lists/connections` | List connections (#19) |

_Note: some endpoints marked "Session" in the API docs may already accept Bearer (the docs appear to be partial). Each endpoint above should be tested with a Bearer token before implementing the API server change._

---

## Legacy Endpoint Discrepancy

The current app calls `GET /api/lists/[id]/items` but the API docs document `GET /api/lists/[id]/data`. The app appears to work today, suggesting the old endpoint still exists. Migration to `/api/lists/[id]/data` is needed for item management features (#10) to use the full CRUD surface.

---

## Implementation Priority

| # | Feature | Priority | API Status |
|---|---------|----------|------------|
| 2 | Message editing | P1 | Ready |
| 3 | Digs (reactions) | P1 | Ready |
| 1 | Tags | P1 | Ready |
| 4 | Reply thread view | P1 | Ready |
| 16 | My Posts filter | P1 | Ready |
| 9 | List create/delete | P2 | Ready |
| 10 | List item CRUD | P2 | Ready (after migration) |
| 11 | Documents | P2 | Ready |
| 8 | Scheduled messages | P2 | Ready (paid) |
| 5 | Notifications | P2 | Needs Bearer |
| 6 | Follow / unfollow | P2 | Needs Bearer |
| 7 | Public user profiles | P2 | Ready |
| 12 | Profile editing | P3 | Needs Bearer |
| 14 | Image/video attach | P3 | Ready (paid) |
| 17 | Forgot password | P3 | UI only |
| 13 | Organizations | P4 | Needs Bearer |
| 15 | Cross-posting | P4 | Needs API work |
| 18 | Data exports | P4 | Needs Bearer |
| 19 | List connections | P4 | Needs Bearer |

---

## Implementation Status

Items implemented in the current development session are marked ✅ above once completed.
