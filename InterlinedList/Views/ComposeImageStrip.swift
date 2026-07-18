//
//  ComposeImageStrip.swift
//  InterlinedList
//

import SwiftUI

/// Horizontal strip of the images attached to a compose draft. Shows each
/// image's upload progress, a retry affordance on failure, and a remove button.
struct ComposeImageStrip: View {
    @ObservedObject var uploader: ComposeImageUploader

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
