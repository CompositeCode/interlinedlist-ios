//
//  ListSkeletonView.swift
//  InterlinedList
//

import SwiftUI

struct ListSkeletonView: View {
    var body: some View {
        List {
            ForEach(0..<8, id: \.self) { i in
                HStack(spacing: 12) {
                    SkeletonBlock(height: 12, cornerRadius: 2).frame(width: 12)
                    SkeletonBlock(height: 13).frame(width: i % 3 == 0 ? 160 : i % 3 == 1 ? 120 : 200)
                    Spacer()
                }
                .padding(.leading, i % 4 > 1 ? 16 : 0)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .allowsHitTesting(false)
    }
}

#Preview {
    ListSkeletonView()
}
