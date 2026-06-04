//
//  InterlinedListApp.swift
//  InterlinedList
//

import SwiftUI

@main
struct InterlinedListApp: App {
    @StateObject private var authState = AuthState()
    @StateObject private var store = AppDataStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authState)
                .environmentObject(store)
                .onChange(of: authState.hasToken) { _, has in
                    if !has { store.reset() }
                }
        }
    }
}
