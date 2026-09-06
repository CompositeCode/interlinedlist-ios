# App Store Listing Copy — InterlinedList iOS

Paste-ready copy for the App Store Connect record, plus the privacy-label and
age-rating answers. Drafted 2026-09-05 against the shipped v1 feature set.

**Hard rule carried through every field below:** no price, no "subscribe", no
"upgrade", no link to pay on the web. Subscriber-only features are described in
neutral product terms or omitted. See `App-Store-Deployment.md` §10 (Guideline
3.1.1 anti-steering).

---

## Name and subtitle

| Field | Value | Length |
|---|---|---|
| **App name** (≤30) | `InterlinedList` | 14 |
| **Subtitle** (≤30) | `Social lists, shared` | 20 |

Subtitle alternatives if the first reads too thin:
- `Lists, docs, and a feed` (23)
- `Write lists. Share threads.` (27)
- `Your lists, your people` (23)

---

## Promotional text (≤170) — changeable without a new submission

```
Nested lists, markdown documents, and a social feed in one place. Post, reply,
share a list with a link, and keep working when you're offline.
```

---

## Description (≤4,000)

```
InterlinedList is a social app for people who think in lists.

Keep your lists and documents where your conversations are. Post to a feed,
reply in threads, follow people, and share any list or document with a link —
without leaving the app.

LISTS THAT NEST
• Build lists inside lists, as deep as you need
• Define your own columns — text, numbers, dates, checkboxes, select options
• Reorder, edit inline, and search across everything
• Back a list with a GitHub repository and work its issues as list rows

DOCUMENTS IN MARKDOWN
• A markdown editor with a formatting toolbar and live preview
• Inline images, folders, and full-text search
• Start from a template instead of a blank page
• Edits are saved locally when you're offline and sync when you're back —
  conflicting changes are preserved side by side, never silently overwritten

A FEED, NOT AN ALGORITHM
• Post text, images, and video; reply, repost, and dig what you like
• Schedule posts, or cross-post to your linked Mastodon, Bluesky, LinkedIn,
  and X accounts
• Follow tags, browse what's trending, and search the feed
• Link previews render as you type

DIRECT MESSAGES
• One-to-one threads with the people you mutually follow
• Send images, see unread counts, and keep conversations near-live

SHARING AND COLLABORATION
• Create share links with view or edit roles, and revoke them at any time
• Invite collaborators to a document by email
• Add watchers to a list and set what each of them can do
• Post on behalf of an organization you own or administer

YOURS TO CONTROL
• Report or block anyone, mute accounts you'd rather not see, and manage your
  blocked and muted lists in Settings
• See every device signed in to your account and sign any of them out
• Export your messages, lists, list rows, and follows as CSV
• Delete your account from inside the app

Requires an interlinedlist.com account. Sign in with email or with Mastodon,
Bluesky, LinkedIn, X, or GitHub.
```

---

## Keywords (≤100 chars, comma-separated, no spaces after commas)

```
lists,checklist,notes,markdown,documents,social,feed,share,collaborate,outline,todo,github
```

(90 characters. Do **not** repeat the app name or the words in it — Apple indexes
those already.)

---

## What's New (v1.0)

```
Initial release.
```

---

## Review notes

```
Demo login:
  Email:    <demo-account-email>
  Password: <demo-account-password>

InterlinedList is a social list-sharing app. The demo account above is a live
production account with sample content in the feed, lists, and documents.

Subscriptions are managed exclusively at interlinedlist.com. There is no
in-app purchase, paywall, price, or billing UI anywhere in this app.

Account deletion: Profile -> Edit Profile -> Delete Account (double-confirm).
Report content:   tap the "..." menu on any post -> Report.
Block a user:     tap the "..." menu on any post, or open their profile -> Block.
Mute a user:      profile -> "..." -> Mute; managed in Settings -> Muted Users.
Blocked list:     Settings -> Blocked Users.

Community guidelines and terms are linked from the registration screen and from
Settings -> About: https://interlinedlist.com/terms
```

---

## Age rating questionnaire

The app is a user-generated-content social network with reporting, blocking, and
muting shipped. Answer honestly; the combination below typically lands at **17+**:

| Question | Answer |
|---|---|
| Unrestricted web access | **No** — links open in the system browser; there is no in-app browser |
| User-generated content | **Yes** — posts, replies, lists, documents, direct messages |
| Does the app have content moderation? | **Yes** — in-app report (message and user), block, mute; server-side moderation |
| Contests, gambling, violence, sexual content, drugs, profanity | **None** authored by the app; UGC is covered by the question above |
| Medical/treatment information | **No** |

---

## App Privacy "nutrition label"

Audited against `APIClient` request bodies on 2026-09-05. The app contains **no
analytics SDK, no ad SDK, and no third-party frameworks at all** — everything below
is sent only to `interlinedlist.com`.

| Data type | ASC category | Purpose | Linked to user? | Used for tracking? |
|---|---|---|---|---|
| Email address | Contact Info | Account management | Yes | No |
| Display name, username, bio | User Content / Contact Info | App functionality | Yes | No |
| Posts, replies, direct messages | User Content | App functionality | Yes | No |
| Lists, list rows, documents | User Content | App functionality | Yes | No |
| Photos and videos (avatar, post media, document images, DM attachments) | User Content → Photos or Videos | App functionality | Yes | No |
| Search queries (feed search, people search, tag autocomplete) | Search History | App functionality | Yes | No |
| User identifier | Identifiers | App functionality | Yes | No |
| Linked OAuth identities (provider + handle) | Identifiers | Account management | Yes | No |
| Device push token | Identifiers → Device ID | App functionality (notifications) | No | No |

**Not collected:** location, contacts, health, financial info, browsing history,
advertising data, diagnostics, or usage analytics. Select **"Data Not Used to Track
You"** for every type.

**Photo access note:** media is chosen through SwiftUI's `PhotosPicker`, which runs
out of process, so the app needs **no** `NSPhotoLibraryUsageDescription` and never
sees the library — only the item the user picks. There is no camera, location,
contacts, or microphone use anywhere in the app, so no other usage-description
strings are required either (verified 2026-09-05).

---

## Field-by-field paste order in App Store Connect

1. **App Information** → Name, Subtitle, Category (Social Networking), Privacy Policy URL
2. **Pricing and Availability** → Free, all territories
3. **Prepare for Submission** → Promotional text, Description, Keywords, Support URL, What's New
4. **App Privacy** → the table above
5. **Age Rating** → the questionnaire above
6. **App Review Information** → demo account + review notes above
