//
//  ComposeImageStrip.swift
//  InterlinedList
//

import SwiftUI
import UniformTypeIdentifiers

/// Horizontal strip of the images attached to a compose draft. Shows each
/// image's upload progress, a retry affordance on failure, and a remove button.
/// Thumbnails drag-to-reorder; attachment order is the post's image order.
struct ComposeImageStrip: View {
    @ObservedObject var uploader: ComposeImageUploader
    @State private var dragging: UUID?

    private let side: CGFloat = 76

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(uploader.attachments) { attachment in
                    thumbnail(attachment)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: side + 12)
    }

    @ViewBuilder
    private func thumbnail(_ attachment: ComposeImageUploader.Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            image(attachment)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { statusOverlay(attachment) }
            removeButton(attachment.id)
                .padding(3)
        }
        .opacity(dragging == attachment.id ? 0.35 : 1)
        .onDrag {
            dragging = attachment.id
            return NSItemProvider(object: attachment.id.uuidString as NSString)
        } preview: {
            image(attachment)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onDrop(
            of: [UTType.text],
            delegate: ReorderDropDelegate(targetId: attachment.id, uploader: uploader, dragging: $dragging)
        )
    }

    @ViewBuilder
    private func image(_ attachment: ComposeImageUploader.Attachment) -> some View {
        if let preview = attachment.preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        }
    }

    @ViewBuilder
    private func statusOverlay(_ attachment: ComposeImageUploader.Attachment) -> some View {
        switch attachment.status {
        case .uploading:
            ZStack {
                Color.black.opacity(0.25)
                ProgressView()
                    .tint(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .failed:
            Button {
                Task { await uploader.retry(attachment.id) }
            } label: {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry").font(.ilMono(11))
                    }
                    .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry failed image upload")
        case .uploaded:
            EmptyView()
        }
    }

    private func removeButton(_ id: UUID) -> some View {
        Button {
            uploader.remove(id)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.ilBody(16))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove image")
    }
}

/// Live drag-to-reorder: as the dragged thumbnail hovers over another, the
/// dragged attachment slots in ahead of it. SwiftUI invokes these callbacks on
/// the main thread, so the `@MainActor` uploader mutation is safe to assume.
private struct ReorderDropDelegate: DropDelegate {
    let targetId: UUID
    let uploader: ComposeImageUploader
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != targetId else { return }
        MainActor.assumeIsolated {
            withAnimation { uploader.moveAttachment(dragging, ahead: targetId) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

#Preview {
    ComposeImageStrip(
        uploader: .previewSeed([
            .uploaded("a"),
            .uploading,
            .failed,
            .uploaded("b")
        ])
    )
    .padding()
}
