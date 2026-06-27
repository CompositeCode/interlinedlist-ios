//
//  DocumentSkeletonView.swift
//  InterlinedList
//

import SwiftUI

struct DocumentSkeletonView: View {
    var body: some View {
        List {
            Section("Folders") {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 10) {
                        SkeletonBlock(height: 12, cornerRadius: 2).frame(width: 16)
                        SkeletonBlock(height: 13).frame(width: 140)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            Section("Documents") {
                ForEach(0..<5, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 5) {
                        SkeletonBlock(height: 14).frame(width: i % 2 == 0 ? 180 : 220)
                        SkeletonBlock(height: 10).frame(width: 80)
                    }
                    .padding(.vertical, 2)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    DocumentSkeletonView()
}
