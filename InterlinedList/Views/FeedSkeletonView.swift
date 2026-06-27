//
//  FeedSkeletonView.swift
//  InterlinedList
//

import SwiftUI

struct FeedSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                FeedSkeletonRow()
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FeedSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SkeletonBlock(height: 12).frame(width: 120)
                Spacer()
                SkeletonBlock(height: 10).frame(width: 45)
            }
            SkeletonBlock(height: 14).frame(maxWidth: .infinity)
            SkeletonBlock(height: 14).frame(width: 200)
            HStack(spacing: 12) {
                SkeletonBlock(height: 10).frame(width: 50)
                SkeletonBlock(height: 10).frame(width: 40)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    FeedSkeletonView()
}
