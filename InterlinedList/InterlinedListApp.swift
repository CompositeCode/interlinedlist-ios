//
//  InterlinedListApp.swift
//  InterlinedList
//

import SwiftUI

@main
struct InterlinedListApp: App {
    @StateObject private var authState = AuthState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
        }
    }
}
