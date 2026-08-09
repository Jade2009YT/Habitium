//
//  DeepLinkCoordinator.swift
//  Habitium
//
//  Bridges widget-triggered AppIntents (which run with the app opened via
//  openAppWhenRun) into in-app navigation: switch tab and present the
//  right sheet. MainTabView observes `pendingLink` and reacts, then clears
//  it so it only fires once.
//

import Observation

@MainActor
@Observable
final class DeepLinkCoordinator {
    var pendingLink: PendingDeepLink?

    /// Call when the app becomes active, in case a widget queued a deep
    /// link while the app was suspended/backgrounded.
    func checkForPendingLink() {
        if let link = SharedDataStore.consumePendingDeepLink() {
            pendingLink = link
        }
    }

    func consume() {
        pendingLink = nil
    }
}
