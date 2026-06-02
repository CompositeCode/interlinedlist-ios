# Plan 14 — Video Upload

## Goal
Wire up the stub video button in `ComposeView` to upload a video via `POST /api/messages/videos/upload` (multipart/form-data) and attach the returned URL to the post. Paid feature — surface a friendly 403 message.

## Endpoint
`POST /api/messages/videos/upload`
- Request: `multipart/form-data`, field name `video`, filename `upload.mp4` (or `.mov`)
- Response: `{ url: String }` (same shape as image upload)

## Files to Change

| File | Change |
|------|--------|
| `InterlinedList/Services/APIClient.swift` | Add `uploadVideo(data:mimeType:)` |
| `InterlinedList/Views/ComposeView.swift` | Wire video button; add `videoUrls` to post body |
| `InterlinedList/Models/Message.swift` | Verify `videoUrls: [String]?` field exists (add if missing) |

## Step-by-Step

### 1. `APIClient.swift` — add `uploadVideo`

Add immediately after `uploadImage(data:mimeType:)` (around line 332):

```swift
func uploadVideo(data: Data, mimeType: String) async throws -> String {
    guard let url = URL(string: baseURL + "/api/messages/videos/upload") else { throw APIError.invalidURL }
    let boundary = UUID().uuidString
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if let token = bearerToken { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let ext = mimeType.contains("mp4") ? "mp4" : "mov"
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"video\"; filename=\"upload.\(ext)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body
    let (responseData, response) = try await session.data(for: request)
    try checkResponse(data: responseData, response: response)
    struct UploadResponse: Decodable { let url: String }
    return try decoder.decode(UploadResponse.self, from: responseData).url
}
```

### 2. `Message.swift` — verify `videoUrls`

Check that `CreateMessageBody` includes `videoUrls: [String]?`. If missing, add it alongside `imageUrls`.

### 3. `ComposeView.swift` — wire the video button

**New state vars:**
```swift
@State private var selectedVideo: PhotosPickerItem?
@State private var uploadedVideoURL: String?
@State private var isUploadingVideo = false
```

**Replace the stub video button** (currently `Button { } label: { Image(systemName: "video.fill") }.disabled(true)`) with a `PhotosPicker` targeting `.videos`:

```swift
PhotosPicker(selection: $selectedVideo, matching: .videos) {
    if isUploadingVideo {
        ProgressView().frame(width: 20, height: 20)
    } else {
        Image(systemName: uploadedVideoURL != nil ? "video.fill" : "video")
            .font(.body)
            .foregroundStyle(uploadedVideoURL != nil ? Color.accentColor : Color.secondary)
    }
}
.buttonStyle(.borderless)
.disabled(isUploadingVideo)
.accessibilityLabel("Attach video")
.onChange(of: selectedVideo) { _, newItem in
    guard let newItem else { return }
    Task { await uploadVideo(newItem) }
}
```

**Add `uploadVideo` function** (mirrors `uploadPhoto`):
```swift
private func uploadVideo(_ item: PhotosPickerItem) async {
    isUploadingVideo = true
    errorMessage = nil
    defer { isUploadingVideo = false }
    do {
        guard let data = try await item.loadTransferable(type: Data.self) else { return }
        let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
        uploadedVideoURL = try await APIClient.shared.uploadVideo(data: data, mimeType: mimeType)
    } catch APIError.status(403) {
        errorMessage = "Video upload requires an active subscription."
        selectedVideo = nil
    } catch {
        errorMessage = "Failed to upload video. Please try again."
        selectedVideo = nil
    }
}
```

**Add video preview row** below the image preview block (or combine into a media preview section):
```swift
if let url = uploadedVideoURL {
    uploadedVideoPreview(url: url)
}
```

**Add `uploadedVideoPreview`** (minimal — just a label + remove button, no inline playback):
```swift
@ViewBuilder
private func uploadedVideoPreview(url: String) -> some View {
    HStack {
        Image(systemName: "video.fill")
            .foregroundStyle(.secondary)
        Text("Video attached")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Button {
            uploadedVideoURL = nil
            selectedVideo = nil
        } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove attached video")
    }
}
```

**Wire `videoUrls` into `postMessage()`** alongside the existing `imageUrls` mapping:
```swift
let videoUrls = uploadedVideoURL.map { [$0] }
_ = try await APIClient.shared.postMessage(
    content: text,
    publiclyVisible: publiclyVisible,
    parentId: replyTo?.id,
    tags: tagList.isEmpty ? nil : tagList,
    scheduledAt: isoScheduled,
    imageUrls: urls,
    videoUrls: videoUrls
)
```

**Add `videoUrls` parameter to `postMessage` in `APIClient`** and include in `CreateMessageBody`.

**Reset `uploadedVideoURL` and `selectedVideo`** in the success alert OK handler alongside the image reset.

## Acceptance Criteria
- Video button in the advanced bar opens `PhotosPicker` for videos.
- Selecting a video uploads it and changes the icon to filled/accent color.
- A "Video attached" row appears below the compose field with a remove button.
- Posting attaches the video URL; the resulting feed `MessageRow` shows the video (existing video preview logic).
- 403 from upload shows "requires subscription" message.
- Build succeeds.
