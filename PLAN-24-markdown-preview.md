# PLAN-24: Markdown Preview in Document Editor

## Problem

`EditDocumentView` and `CreateDocumentView` both show a plain multiline `TextField` for content. The user has no way to see how the markdown will render while editing — they have to save and navigate back to `DocumentDetailView` to verify formatting.

`DocumentDetailView` already renders markdown correctly using `AttributedString(markdown:)`.

## Solution

Add a **Preview toggle** to both the Create and Edit document sheets. When Preview is active:
- The textarea is replaced by a rendered `AttributedString` view (same rendering as `DocumentDetailView`)
- The toolbar shows "Edit" to return to the editor
- When Edit is active, the toolbar shows "Preview" to switch to the preview

This is a pure UI change — no new API calls needed.

## UI Design

### Toolbar toggle button

Add a `ToolbarItem(placement: .topBarTrailing)` (alongside the existing Save/Create button):

```
[Cancel]   [Preview ▸]   [Save]
```

When in preview mode:

```
[Cancel]   [◂ Edit]   [Save]
```

The Save/Create button remains accessible in both modes so the user does not have to exit preview to save.

### Preview rendering

Reuse the same markdown rendering logic already in `DocumentDetailView`:

```swift
if let attributed = try? AttributedString(markdown: content,
    options: .init(interpretedSyntax: .full)) {
    ScrollView {
        Text(attributed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }
}
```

Show a "No content" placeholder (italic, secondary color) when `content` is empty.

### State

```swift
@State private var showingPreview = false
```

Toggle between the `TextField` and the `ScrollView` based on this flag. No animation needed — a simple `if/else` swap is sufficient.

## Files to Modify

| File | Action |
|---|---|
| `InterlinedList/Views/DocumentsView.swift` | Add preview toggle to `CreateDocumentView` and `EditDocumentView` |

Both `CreateDocumentView` and `EditDocumentView` live in `DocumentsView.swift` as private structs. Both need the same change.

## Implementation Details

### `CreateDocumentView` changes

1. Add `@State private var showingPreview = false`
2. In the `"Content (Markdown)"` Section, replace the static `TextField` with:
   ```swift
   if showingPreview {
       previewContent
   } else {
       TextField("Write in markdown…", text: $content, axis: .vertical)
           .lineLimit(8...20)
           .font(.system(.body, design: .monospaced))
   }
   ```
3. Add toolbar button that toggles `showingPreview`

### `EditDocumentView` changes

Same three changes. The initial value of `content` is `document.content ?? ""` (already set).

### Extracted private view

To avoid duplicating the rendering code, extract a `private var previewContent: some View` computed property inside each struct:

```swift
private var previewContent: some View {
    Group {
        if content.isEmpty {
            Text("No content")
                .foregroundStyle(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let attributed = try? AttributedString(markdown: content,
            options: .init(interpretedSyntax: .full)) {
            Text(attributed)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .padding(.vertical, 4)
}
```

## No New Tests Required

This is purely a UI toggle with no new networking or model logic. Preview correctness is verified manually. The existing `DocumentModelTests` and `APIClientDocumentsTests` are unaffected.

## Acceptance Criteria
- [ ] Create Document sheet: tapping "Preview" replaces the text field with rendered markdown
- [ ] Edit Document sheet: same behavior, pre-filled from existing content
- [ ] Switching back to Edit mode shows the textarea with content intact (no data loss)
- [ ] Save/Create buttons work from both Edit and Preview modes
- [ ] Empty content shows "No content" placeholder in preview
- [ ] Markdown formatting (bold, italic, lists, links, headings) renders correctly
- [ ] `#Preview` blocks compile and demonstrate both editor and preview states
