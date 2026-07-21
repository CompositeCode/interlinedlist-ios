//
//  MarkdownEditor.swift
//  InterlinedList
//

import PhotosUI
import SwiftUI
import UIKit

/// Command bus between the SwiftUI formatting toolbar and the live `UITextView`.
///
/// SwiftUI's `TextEditor` doesn't expose the selection, so formatting that acts
/// on the caret/selection has to reach into a `UITextView`. The toolbar calls
/// these methods; the representable's coordinator installs `handler` to apply
/// them against the text view that actually owns the selection.
@MainActor
final class MarkdownEditorController: ObservableObject {
    fileprivate var handler: ((Command) -> Void)?

    enum Command {
        case wrap(prefix: String, suffix: String, placeholder: String)
        case linePrefix(String)
        case insert(String, selectWithin: NSRange?)
        case focus
    }

    func bold() { handler?(.wrap(prefix: "**", suffix: "**", placeholder: "bold")) }
    func italic() { handler?(.wrap(prefix: "_", suffix: "_", placeholder: "italic")) }
    func code() { handler?(.wrap(prefix: "`", suffix: "`", placeholder: "code")) }
    func link() { handler?(.wrap(prefix: "[", suffix: "](https://)", placeholder: "text")) }
    func heading() { handler?(.linePrefix("## ")) }
    func bullet() { handler?(.linePrefix("- ")) }
    func quote() { handler?(.linePrefix("> ")) }
    func focus() { handler?(.focus) }

    /// Inserts `![alt](url)` at the caret and selects the alt text so the user
    /// can immediately type a caption over the placeholder.
    func insertImage(alt: String, url: String) {
        let snippet = "\n![\(alt)](\(url))\n"
        let altStart = ("\n![" as NSString).length
        let selection = NSRange(location: altStart, length: (alt as NSString).length)
        handler?(.insert(snippet, selectWithin: selection))
    }
}

/// A `UITextView`-backed markdown editor: monospaced, full-height, with two-way
/// text binding plus programmatic edits driven through `MarkdownEditorController`.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, controller: controller)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = UIColor(ILColor.textBody)
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.isScrollEnabled = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.text = text
        context.coordinator.textView = textView
        context.coordinator.install()
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.textBinding = $text
        if uiView.text != text {
            let caret = min(uiView.selectedRange.location, (text as NSString).length)
            uiView.text = text
            uiView.selectedRange = NSRange(location: caret, length: 0)
        }
        context.coordinator.install()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var textBinding: Binding<String>
        let controller: MarkdownEditorController
        weak var textView: UITextView?

        init(text: Binding<String>, controller: MarkdownEditorController) {
            self.textBinding = text
            self.controller = controller
        }

        /// Point the controller at this coordinator. Re-run on every update since
        /// SwiftUI may recreate the representable while keeping the coordinator.
        func install() {
            controller.handler = { [weak self] command in
                self?.apply(command)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            textBinding.wrappedValue = textView.text
        }

        // MARK: - Command application

        private func apply(_ command: MarkdownEditorController.Command) {
            guard let textView else { return }
            switch command {
            case .focus:
                textView.becomeFirstResponder()
            case .insert(let snippet, let selectWithin):
                let location = textView.selectedRange.location
                let selectAfter: NSRange
                if let selectWithin {
                    selectAfter = NSRange(location: location + selectWithin.location, length: selectWithin.length)
                } else {
                    selectAfter = NSRange(location: location + (snippet as NSString).length, length: 0)
                }
                replace(textView, range: textView.selectedRange, with: snippet, select: selectAfter)
            case .wrap(let prefix, let suffix, let placeholder):
                wrap(textView, prefix: prefix, suffix: suffix, placeholder: placeholder)
            case .linePrefix(let marker):
                linePrefix(textView, marker: marker)
            }
        }

        private func wrap(_ textView: UITextView, prefix: String, suffix: String, placeholder: String) {
            let content = textView.text as NSString
            let range = textView.selectedRange
            let prefixLength = (prefix as NSString).length
            if range.length > 0 {
                let selected = content.substring(with: range)
                let selectedLength = (selected as NSString).length
                replace(textView, range: range, with: prefix + selected + suffix,
                        select: NSRange(location: range.location + prefixLength, length: selectedLength))
            } else {
                replace(textView, range: range, with: prefix + placeholder + suffix,
                        select: NSRange(location: range.location + prefixLength, length: (placeholder as NSString).length))
            }
        }

        private func linePrefix(_ textView: UITextView, marker: String) {
            let content = textView.text as NSString
            let selection = textView.selectedRange
            var lineStart = selection.location
            while lineStart > 0, content.character(at: lineStart - 1) != 10 {
                lineStart -= 1
            }
            let markerLength = (marker as NSString).length
            replace(textView, range: NSRange(location: lineStart, length: 0), with: marker,
                    select: NSRange(location: selection.location + markerLength, length: selection.length))
        }

        /// Replace `range` with `string`, set the selection, and push the result
        /// into the binding (programmatic edits don't fire `textViewDidChange`).
        private func replace(_ textView: UITextView, range: NSRange, with string: String, select: NSRange) {
            let content = textView.text as NSString
            textView.text = content.replacingCharacters(in: range, with: string)
            textView.selectedRange = select
            textBinding.wrappedValue = textView.text
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
            }
        }
    }
}

/// Full editing surface for a document's markdown: a Write/Preview toggle, the
/// `UITextView` editor with a keyboard formatting toolbar, and image insertion
/// (upload progress inline, markdown written at the caret). Image upload is
/// injected so the edit flow uploads doc-scoped and the create flow can
/// auto-save a draft first.
struct DocumentContentEditor: View {
    @Binding var content: String
    let uploadImage: (Data, String) async throws -> String

    @StateObject private var controller = MarkdownEditorController()
    @State private var mode: Mode = .write
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var imageError: String?

    enum Mode: Hashable { case write, preview }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Editing mode", selection: $mode) {
                Text("Write").tag(Mode.write)
                Text("Preview").tag(Mode.preview)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityLabel("Editing mode")

            Divider()

            switch mode {
            case .write:
                formatBar
                Divider()
                MarkdownTextView(text: $content, controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .preview:
                ScrollView {
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Nothing to preview yet.")
                            .font(.ilBody())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        MarkdownView(content: content)
                            .padding()
                    }
                }
            }

            if let imageError {
                Text(imageError)
                    .font(.ilMono())
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
    }

    // A persistent toolbar (rather than a `.keyboard`-placement one) so it works
    // reliably above the UIKit-backed text view and stays reachable in Write mode.
    private var formatBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                formatButton("bold", "Bold") { controller.bold() }
                formatButton("italic", "Italic") { controller.italic() }
                formatButton("number", "Heading") { controller.heading() }
                formatButton("list.bullet", "Bullet list") { controller.bullet() }
                formatButton("text.quote", "Quote") { controller.quote() }
                formatButton("chevron.left.forwardslash.chevron.right", "Inline code") { controller.code() }
                formatButton("link", "Link") { controller.link() }
                Divider().frame(height: 22).padding(.horizontal, 4)
                imageButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var imageButton: some View {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Group {
                if isUploadingImage {
                    ProgressView()
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 17))
                        .foregroundStyle(ILColor.primary)
                }
            }
            .frame(width: 40, height: 34)
        }
        .disabled(isUploadingImage)
        .accessibilityLabel(isUploadingImage ? "Uploading image" : "Insert image")
    }

    private func formatButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(ILColor.primary)
                .frame(width: 40, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        imageError = nil
        isUploadingImage = true
        defer { isUploadingImage = false; selectedPhoto = nil }
        guard let rawData = try? await item.loadTransferable(type: Data.self) else {
            imageError = "Failed to load image."
            return
        }
        let uploadData: Data
        let mimeType: String
        if let processed = await Task.detached(priority: .userInitiated, operation: {
            ImageUploadProcessor.process(rawData)
        }).value {
            uploadData = processed.data
            mimeType = processed.mimeType
        } else {
            uploadData = rawData
            mimeType = rawData.starts(with: [0x89, 0x50]) ? "image/png" : "image/jpeg"
        }
        do {
            let url = try await uploadImage(uploadData, mimeType)
            controller.focus()
            controller.insertImage(alt: "image", url: url)
        } catch APIError.status(401) {
            imageError = "Your session expired. Please sign in again."
        } catch {
            imageError = "Image upload failed."
        }
    }
}

#Preview {
    struct PreviewHost: View {
        @State private var content = "# Title\n\nSome **markdown** text."
        var body: some View {
            NavigationStack {
                DocumentContentEditor(content: $content) { _, _ in
                    "https://example.com/image.jpg"
                }
                .navigationTitle("Editor")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    return PreviewHost()
}
