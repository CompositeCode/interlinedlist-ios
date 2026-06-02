# PLAN-21: List Schema Editor & Edit List Metadata

## Problem

Once a list exists there is no way in the iOS app to:
- Rename the list or change its description
- Change the list's public/private visibility
- Add a new column (e.g. "Rating" number field)
- Reorder, rename, or delete existing columns
- Change a column's required flag or type

The backend has full support for all of this via `PUT /api/lists/[id]/schema`.

Additionally: **visibility (`isPublic`)** cannot be changed through `PUT /api/lists/[id]` (that route only accepts `title`, `description`, `parentId`). Visibility must go through `PUT /api/lists/[id]/schema`, which also updates the title/description via the DSL `title`/`description` fields.

## API Contract

### `GET /api/lists/[id]/schema`
Returns the current schema as DSL:
```json
{
  "data": {
    "title": "My List",
    "description": "...",
    "fields": [
      { "key": "name", "type": "text", "label": "Name", "required": true, "displayOrder": 0 }
    ]
  }
}
```

### `PUT /api/lists/[id]/schema`
Updates the full schema (replaces all properties):
```json
{
  "schema": { "title": "...", "description": "...", "fields": [...] },
  "isPublic": true
}
```
Response: `{ "message": "Schema updated successfully", "data": updatedList }`

## New `APIClient` Methods

```swift
func listSchemaAsDSL(listId: String) async throws -> DSLSchema
func updateListSchema(listId: String, schema: DSLSchema, isPublic: Bool) async throws -> UserList
func updateListMetadata(listId: String, title: String, description: String?, parentId: String?) async throws -> UserList
```

`updateListSchema` sends `PUT /api/lists/[id]/schema`.
`updateListMetadata` sends `PUT /api/lists/[id]` (title/description only, no visibility).

## New View: `EditListView`

Presented as a sheet from `ListDetailView` toolbar menu ("Edit List").

### Sections

**Details section**
- Name field (pre-filled)
- Description field (pre-filled, optional)
- Public/Private toggle (pre-filled from `list.isPublic`)

**Columns section**
- Rows for each existing column:
  - Column name (editable inline)
  - Type chip (Text, Number, etc. — tap to change via picker)
  - Required badge (toggle)
  - Drag handle for reorder (`.onMove`)
  - Swipe-to-delete
- "Add Column" button at the bottom of the section
  - Opens `AddColumnSheet`: name field, type picker, required toggle, options list for select types

**Toolbar**
- Cancel (dismisses without saving)
- Save (sends `PUT /api/lists/[id]/schema` with full new DSL, then updates `ListDetailView`)

### State management
Load current schema via `GET /api/lists/[id]/schema` on appear.
Represent each column as a local `EditableColumn` value type:
```swift
struct EditableColumn: Identifiable {
    var id: String = UUID().uuidString  // temporary for new cols; use propertyKey for existing
    var key: String
    var label: String
    var type: String
    var required: Bool
    var options: [String]
    var displayOrder: Int
}
```
Build DSL from the current state of `EditableColumn` array when Save is tapped.

### Key column type picker options (matching backend DSL)
| Display Name | DSL type value |
|---|---|
| Text | `text` |
| Long text | `textarea` |
| Number | `number` |
| Checkbox | `boolean` |
| Date | `date` |
| Date & Time | `datetime` |
| URL | `url` |
| Email | `email` |
| Phone | `tel` |
| Dropdown | `select` |
| Multi-select | `multiselect` |
| Priority | `priority` |

## `ListDetailView` Changes

- Add a toolbar menu item "Edit List" (pencil icon or `ellipsis.circle` menu)
- After successful save in `EditListView`, reload the list schema and item list

## Files to Create / Modify

| File | Action |
|---|---|
| `InterlinedList/Services/APIClient.swift` | Add `listSchemaAsDSL`, `updateListSchema`, `updateListMetadata` |
| `InterlinedList/Models/List.swift` | `DSLSchema`/`DSLField` types (if not added in PLAN-20) |
| `InterlinedList/Views/ListsView.swift` | Add "Edit List" toolbar menu in `ListDetailView` |
| `InterlinedList/Views/EditListView.swift` | New file |

## Unit Tests

**`APIClientListsTests.swift`**
- `test_listSchemaAsDSL_sendsGetToCorrectPath`
- `test_updateListSchema_sendsPutWithSchemaBody`
- `test_updateListSchema_decodesDataWrapper`

## Acceptance Criteria
- [ ] Long-pressing or using toolbar menu on a list opens Edit List sheet pre-filled with current name, description, columns
- [ ] Columns can be added, reordered (drag), and deleted
- [ ] Column type is changeable; select type shows options editor
- [ ] Visibility toggle works and persists
- [ ] Save sends `PUT /api/lists/[id]/schema`, success updates the list header and schema
- [ ] 401 routes to logout; server errors surface inline
