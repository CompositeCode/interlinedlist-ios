# PLAN-20: Fix Create List Flow

## Problem

Tapping "Create" in `CreateListView` always shows "Failed to create list." The root causes are:

1. **Response wrapper mismatch** — `POST /api/lists` returns `{ message: "...", data: createdList }` but `APIClient.createList` decodes a `{ list: UserList? }` wrapper. `response.list` is always `nil`, so the guard throws `APIError.noData`.

2. **Missing subscription handling** — The backend returns 403 with `{ "error": "Subscribe to create lists." }` when the user isn't a subscriber. `CreateListView` doesn't distinguish this from a generic error.

3. **Missing schema (columns) step** — `POST /api/lists` accepts an optional `schema` DSL field. Without it the list is created with zero columns. When the user then navigates into that list, no schema is loaded, `addableProperty` is `nil`, and the "Add item" row is hidden. The list is effectively unusable until columns are defined.

## Solution

Extend `CreateListView` into a two-step sheet:

- **Step 1** — Name, description, and visibility (existing). "Next" advances to step 2.
- **Step 2** — Column builder: add one or more columns with name, type, and required flag. At least one column is required before "Create" is enabled.

The `APIClient.createList` method sends both the metadata and the DSL schema in one POST.

## API Contract

### `POST /api/lists`
**Request:**
```json
{
  "title": "My List",
  "description": "Optional",
  "isPublic": true,
  "schema": {
    "title": "My List",
    "description": "Optional",
    "fields": [
      { "key": "name", "type": "text", "label": "Name", "required": true }
    ]
  }
}
```

**Response (201):**
```json
{ "message": "List created successfully", "data": { "id": "...", "title": "...", ... } }
```
Note: response key is `data`, **not** `list`.

**Response (403):** `{ "error": "Subscribe to create lists." }`

### DSL field types (valid values)
`text`, `number`, `date`, `datetime`, `boolean`, `select`, `multiselect`, `textarea`, `email`, `url`, `tel`, `priority`

`select` and `multiselect` require an `options: [String]` array.

## Files to Change

### `InterlinedList/Services/APIClient.swift`
- `createList(title:description:isPublic:)` → add `schema` parameter (DSL JSON `Encodable` struct)
- Decode response from `{ data: UserList }` instead of `{ list: UserList }`
- Add `APIError.status(403)` handling in callers

### `InterlinedList/Models/List.swift`
Add DSL schema types for encoding:

```swift
struct DSLField: Encodable {
    let key: String
    let type: String      // "text", "number", "boolean", etc.
    let label: String
    let required: Bool
    var options: [String]? // required for select/multiselect
    var placeholder: String?
    var helpText: String?
    var displayOrder: Int
}

struct DSLSchema: Encodable {
    let title: String
    let description: String?
    let fields: [DSLField]
}
```

### `InterlinedList/Views/CreateListView.swift`
Replace the current single-step form with a two-step flow:

**Step 1 — Details**
- Name (required)
- Description (optional)
- Public/Private toggle
- "Next →" button (disabled until name is non-empty)

**Step 2 — Columns**
- List of added columns (name, type chip, required badge, delete button)
- "Add Column" row that expands inline or opens a sub-sheet:
  - Column Name field
  - Type picker: Text, Number, Boolean (checkbox), Date, URL, Email, Select
  - Required toggle
  - For Select type: options list (add/remove individual options)
- "Create List" button (disabled until at least one column exists)
- "← Back" to return to step 1

**Error handling:**
- 403 → "Creating lists requires an active subscription."
- Other server errors → show `error` message from response
- Generic fallback → "Failed to create list."

## Unit Tests (`InterlinedListTests/APIClientTests/APIClientListsTests.swift`)
- `test_createList_sendsSchemaInBody` — stub 201, verify `schema` key present in body
- `test_createList_decodesDataWrapper` — stub `{ "data": {...} }`, assert result non-nil
- `test_createList_403_throwsSubscriptionError` — stub 403 with error JSON, assert `APIError.server`

## Acceptance Criteria
- [ ] Tapping Create → Next → (add ≥1 column) → Create successfully creates the list and returns to the Lists screen
- [ ] The new list immediately shows the correct column headers when opened
- [ ] Creating without a subscription shows "requires an active subscription" message
- [ ] Validation: Next disabled with empty name; Create disabled with zero columns
- [ ] Preview blocks compile and render step 1 and step 2 independently
