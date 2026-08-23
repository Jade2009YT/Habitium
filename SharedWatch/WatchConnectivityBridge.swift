//
//  WatchConnectivityBridge.swift
//  Habitium (shared between the iOS app and the watchOS app ONLY — not
//  the widget extension, which can't reliably use WatchConnectivity)
//
//  App Groups don't help here: they share storage between an app and its
//  extensions on the SAME device, but the iPhone and the Watch are two
//  separate physical devices with separate storage. Getting data from one
//  to the other needs an actual transfer, which is what WatchConnectivity
//  is for.
//
//  v1 scope: one-way, iPhone -> Watch, "latest state wins" glanceable
//  data — the same four snapshots that already feed the iOS widgets.
//  `updateApplicationContext` is the right primitive for this: it always
//  holds just the most recent payload (older ones are discarded, not
//  queued), delivered next time the Watch app is reachable, no need for
//  either app to be in the foreground. Read-write sync (e.g. marking a
//  dose taken *from* the Watch) is a deliberately separate, harder
//  follow-up — see README.
//

import Foundation
import Observation
import WatchConnectivity

struct WatchSyncPayload: Codable {
    var nutrition: NutritionWidgetSnapshot
    var finance: FinanceWidgetSnapshot
    var calendar: CalendarWidgetSnapshot
    var medication: MedicationWidgetSnapshot
}

@MainActor
@Observable
final class WatchConnectivityBridge: NSObject {

    static let shared = WatchConnectivityBridge()

    /// The last payload this device has (received on watchOS, or the one
    /// most recently sent on iOS) — the Watch app's views read this
    /// directly.
    private(set) var latestPayload: WatchSyncPayload?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()

        #if os(watchOS)
        // Hydrate immediately from whatever context was last delivered,
        // even before this launch — WCSession caches it.
        if let data = session?.receivedApplicationContext["payload"] as? Data,
           let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) {
            latestPayload = payload
        }
        #endif
    }

    #if os(iOS)
    /// Call after any repository write that already refreshes the widget
    /// snapshots — bundles the four current snapshots and pushes them to
    /// the paired Watch (if any).
    func sendCurrentSnapshots() {
        guard let session, session.activationState == .activated else { return }
        let payload = WatchSyncPayload(
            nutrition: SharedDataStore.readNutritionSnapshot(),
            finance: SharedDataStore.readFinanceSnapshot(),
            calendar: SharedDataStore.readCalendarSnapshot(),
            medication: SharedDataStore.readMedicationSnapshot()
        )
        latestPayload = payload
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? session.updateApplicationContext(["payload": data])
    }
    #endif
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        Task { @MainActor in self.sendCurrentSnapshots() }
        #endif
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["payload"] as? Data,
              let payload = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) else { return }
        Task { @MainActor in
            WatchConnectivityBridge.shared.latestPayload = payload
        }
    }
}
