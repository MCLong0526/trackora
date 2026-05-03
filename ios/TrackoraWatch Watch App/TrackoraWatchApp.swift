//
//  TrackoraWatchApp.swift
//  TrackoraWatch Watch App
//

import SwiftUI

@main
struct TrackoraWatch_Watch_AppApp: App {
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onAppear { session.activate() }
        }
    }
}
