//
//  PendingWidgetActions.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Interactive widgets can't touch SwiftData directly (the store's model
//  types live only in the app target), so widget-triggered AppIntents
//  queue a lightweight, Codable "pending action" here instead. The app
//  drains the queue against the real SwiftData store the next time it
//  becomes active (see PendingActionProcessor). Optimistic UI updates
//  (e.g. removing a completed task from the widget instantly) are done by
//  also rewriting the relevant snapshot at the same time.
//

import Foundation

enum PendingDeepLink: String, Codable {
    case scanFood
    case addExpense
}

extension SharedDataStore {
    private static var pendingCompletionsKey: String { "widget.pending.taskCompletions" }
    private static var pendingDeepLinkKey: String { "widget.pending.deepLink" }

    static func queueTaskCompletion(id: UUID) {
        var ids = pendingTaskCompletions()
        guard !ids.contains(id) else { return }
        ids.append(id)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults(suiteName: AppGroup.identifier)?.set(data, forKey: pendingCompletionsKey)
        }
    }

    static func pendingTaskCompletions() -> [UUID] {
        guard let data = UserDefaults(suiteName: AppGroup.identifier)?.data(forKey: pendingCompletionsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return ids
    }

    static func clearPendingTaskCompletions() {
        UserDefaults(suiteName: AppGroup.identifier)?.removeObject(forKey: pendingCompletionsKey)
    }

    static func writePendingDeepLink(_ link: PendingDeepLink) {
        UserDefaults(suiteName: AppGroup.identifier)?.set(link.rawValue, forKey: pendingDeepLinkKey)
    }

    static func consumePendingDeepLink() -> PendingDeepLink? {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        guard let raw = defaults?.string(forKey: pendingDeepLinkKey), let link = PendingDeepLink(rawValue: raw) else {
            return nil
        }
        defaults?.removeObject(forKey: pendingDeepLinkKey)
        return link
    }
}
