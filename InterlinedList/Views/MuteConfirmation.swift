//
//  MuteConfirmation.swift
//  InterlinedList
//

import SwiftUI

/// The mute confirmation + failure alert, shared by every post menu so the copy
/// distinguishing mute from block is written once.
private struct MuteConfirmationModifier: ViewModifier {
    @Binding var target: MuteTarget?
    @Binding var errorMessage: String?
    let onConfirm: (MuteTarget) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                target.map { MuteCopy.confirmTitle($0.username) } ?? "",
                isPresented: Binding(
                    get: { target != nil },
                    set: { if !$0 { target = nil } }
                ),
                titleVisibility: .visible,
                presenting: target
            ) { presented in
                Button("Mute", role: .destructive) { onConfirm(presented) }
                Button("Cancel", role: .cancel) { target = nil }
            } message: { _ in
                Text(MuteCopy.confirmMessage)
            }
            .alert(
                "Mute failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

extension View {
    func muteConfirmation(
        target: Binding<MuteTarget?>,
        errorMessage: Binding<String?>,
        onConfirm: @escaping (MuteTarget) -> Void
    ) -> some View {
        modifier(MuteConfirmationModifier(target: target, errorMessage: errorMessage, onConfirm: onConfirm))
    }
}

#Preview {
    StatefulPreviewWrapper()
}

private struct StatefulPreviewWrapper: View {
    @State private var target: MuteTarget? = MuteTarget(id: "1", username: "alice")
    @State private var errorMessage: String?

    var body: some View {
        Text("Mute confirmation")
            .muteConfirmation(target: $target, errorMessage: $errorMessage) { _ in target = nil }
    }
}
