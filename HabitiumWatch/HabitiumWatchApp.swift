//
//  HabitiumWatchApp.swift
//  HabitiumWatch
//
//  Entry point for the watchOS companion app. v1 is read-only/glanceable —
//  it shows whatever the iPhone last synced via WatchConnectivityBridge.
//  No SwiftData, no local decisions: the Watch app is intentionally dumb,
//  the iPhone stays the source of truth.
//

import SwiftUI

@main
struct HabitiumWatchApp: App {
    @State private var bridge = WatchConnectivityBridge.shared

    var body: some Scene {
        WindowGroup {
            WatchSummaryView()
                .environment(bridge)
        }
    }
}
