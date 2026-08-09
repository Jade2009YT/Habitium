//
//  PendingActionProcessor.swift
//  Habitium
//
//  Drains widget-queued actions (currently just task completions — see
//  CompleteTaskIntent) against the real SwiftData store. Call on app
//  launch and whenever the app becomes active.
//

import Foundation

@MainActor
enum PendingActionProcessor {
    static func processPendingTaskCompletions(using repository: PlannerRepository) {
        let ids = SharedDataStore.pendingTaskCompletions()
        guard !ids.isEmpty else { return }

        let allTasks = repository.tasks(on: nil)
        for id in ids {
            guard let task = allTasks.first(where: { $0.id == id }), !task.isCompleted else { continue }
            repository.toggleComplete(task)
        }
        SharedDataStore.clearPendingTaskCompletions()
    }
}
