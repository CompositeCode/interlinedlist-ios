//
//  SkeletonBlock.swift
//  InterlinedList
//

import SwiftUI

struct SkeletonBlock: View {
    var height: CGFloat = 14
    var cornerRadius: CGFloat = 6

    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemFill))
            .frame(height: height)
            .opacity(animate ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}
