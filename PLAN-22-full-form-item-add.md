# PLAN-22: Full-Form Item Add & Edit Modal

## Problem

`ListDetailView` currently shows a single inline text field to add a row. This only works for lists where the first visible property is a simple text/email/URL field. It fails silently for:

- Lists with multiple required fields (only the first is populated; others are left blank)
- Lists whose first visible field is boolean, number, date, select, or priority (no appropriate text input)
- Lists with no `addableProperty` (shows "Add item not supported for this list type")

There is also no way to edit an existing row's fields — the current `updateField` is per-field only (toggling a boolean), with no full-row editing surface.

## Solution

### 1. Row Add Modal — `AddListItemView`

When the user taps "Add Item" (currently the inline field), present a sheet `AddListItemView` that shows **all visible schema fields** as appropriate input controls, one per row.

The sheet is driven entirely by the `[ListPropertyDef]` schema already loaded in `ListDetailView`.

**Field control mapping:**

| `propertyType` | Control |
|---|---|
| `text` | `TextField` |
| `textarea` | `TextField(axis: .vertical)` (multiline) |
| `email` | `TextField` with `.keyboardType(.emailAddress)` |
| `url` | `TextField` with `.keyboardType(.URL)` |
| `tel` | `TextField` with `.keyboardType(.phonePad)` |
| `number` | `TextField` with `.keyboardType(.decimalPad)`, stores as `JSONValue.number` |
| `boolean` | `Toggle` |
| `date` | `DatePicker` (date only) |
| `datetime` | `DatePicker` (date + time) |
| `select` | `Picker` (wheel or menu) showing `validationRules.options` |
| `multiselect` | Tappable chip list (toggle inclusion of each option) |
| `priority` | Segmented `Picker` (Low / Medium / High / Critical) |

Required fields are marked with a red asterisk next to the label. Save is disabled while any required field is empty.

### 2. Row Edit Modal — `EditListItemView`

Identical structure to `AddListItemView`, pre-filled with the row's existing `rowData`. Opened by tapping a row in the list (currently navigation-linked but `ListDetailView` has no navigation destination for items).

Calls `APIClient.updateRow(listId:itemId:key:value:)` for each changed field, or a batch update if the backend supports it (currently single-field PUT — batching by sending the full `data` dict is also fine since the backend accepts `{ "data": { ... } }`).

### 3. Remove Inline Add Field

The current `addItemFooter` is removed. A new "Add Item" toolbar button (or floating `+` button inside the list) opens `AddListItemView`.

## Files to Modify / Create

| File | Action |
|---|---|
| `InterlinedList/Views/ListsView.swift` | Remove `addItemFooter`, add toolbar "Add" button, add `.sheet` for add/edit, pass schema to both sheets |
| `InterlinedList/Views/AddListItemView.swift` | New file — add modal |
| `InterlinedList/Views/EditListItemView.swift` | New file — edit modal (share field-render logic via extracted `ListItemFormView`) |

## Shared form component — `ListItemFormView`

```swift
struct ListItemFormView: View {
    let schema: [ListPropertyDef]
    @Binding var values: [String: JSONValue]   // keyed by propertyKey
    // ...
}
```

Both `AddListItemView` and `EditListItemView` embed `ListItemFormView`, keeping field-rendering in one place.

## `APIClient` Changes

The existing `addListItem(listId:firstPropertyKey:value:)` is replaced or supplemented by:

```swift
func addListItem(listId: String, data: [String: JSONValue]) async throws -> ListItem
```

The body is `{ "data": { ... } }` (same shape the backend already accepts).

## Unit Tests (`APIClientListsTests.swift`)
- `test_addListItem_sendsPostWithFullDataDict` — verify body contains all keys
- `test_addListItem_decodesRowWrapper`

## Acceptance Criteria
- [ ] Tapping "Add Item" opens a modal with one input per visible schema field
- [ ] Required fields are marked; Save is disabled while any required field is empty
- [ ] Number, date, boolean, select fields use appropriate native controls
- [ ] Tapping an existing row opens the edit modal pre-filled with current values
- [ ] Adding and editing successfully update the list without a full reload
- [ ] 401 routes to logout; server errors show inline in the sheet
