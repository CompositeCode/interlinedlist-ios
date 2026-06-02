# Plan 10 — List Items: Verify `/data` Endpoint Migration & Full CRUD

## Status
The `listItems(listId:)` function in `APIClient.swift` already calls `/api/lists/[id]/data` (not the legacy `/items`). The migration is effectively done. This plan confirms it and fills any remaining gaps in the item-management surface.

## Goals
1. Confirm `listItems` calls `/data` and handles both response shapes (`rows` vs `items`).
2. Confirm `addListItem`, `deleteListItem`, and `updateRow` (toggle) all use `/data`.
3. Verify the UI wires up correctly — new-item text field, swipe-to-delete, checkmark toggle.
4. Update `GAP-DEV.md` to mark the migration sub-item ✅.

## Audit Checklist

### `InterlinedList/Services/APIClient.swift`
- [ ] `listItems(listId:)` — line ~193: calls `/api/lists/\(encoded)/data`; decodes `rows` then falls back to `items`. **Already correct.**
- [ ] `addListItem(listId:firstPropertyKey:value:)` — line ~237: POSTs to `/api/lists/\(encoded)/data`. **Already correct.**
- [ ] `updateRow(listId:itemId:key:value:)` — line ~227: PATCHes `/api/lists/\(encodedList)/data/\(encodedItem)`. **Already correct.**
- [ ] `deleteListItem(listId:itemId:)` — line ~246: DELETEs `/api/lists/\(encodedList)/data/\(encodedItem)`. **Already correct.**

### `InterlinedList/Views/ListsView.swift`
- [ ] Verify `ListDetailView` calls `APIClient.shared.listItems(listId:)` in its `.task {}`.
- [ ] Verify add-item text field calls `APIClient.shared.addListItem(...)` on submit.
- [ ] Verify swipe-to-delete calls `APIClient.shared.deleteListItem(...)`.
- [ ] Verify checkmark tap calls `APIClient.shared.updateRow(...)` with the bool key.

## Implementation Steps

1. **Open `ListsView.swift`** and trace `ListDetailView` end-to-end against the checklist above.
2. If any call still references `/items` directly (e.g. a hardcoded path), fix it to use the `APIClient` methods above.
3. If the response shape from `/data` returns rows without a `checked` / `completed` field, confirm which `propertyKey` the schema uses for the boolean toggle and make sure `updateRow` sends the right key.
4. Build and run on simulator; open a list, add an item, toggle its checkmark, swipe-delete it.
5. Edit `GAP-DEV.md`: change the migration sub-item from `🔲` to `✅`.

## Acceptance Criteria
- Adding an item via the text field persists after pull-to-refresh.
- Tapping the checkmark updates the row optimistically and survives a refresh.
- Swiping to delete removes the item from the server.
- No calls to `/api/lists/[id]/items` remain in the codebase (`grep -r "/items" InterlinedList/` returns no list-item hits).
- Build succeeds with zero warnings added.
