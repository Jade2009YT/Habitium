//
//  PendingActionProcessor.swift
//  Habitium
//
//  Drains widget-queued actions (task completions — CompleteTaskIntent —
//  and medication doses — MarkDoseTakenIntent) against the real SwiftData
//  store. Call on app launch and whenever the app becomes active.
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

    static func processPendingMedicationDoses(using repository: MedicationRepository) {
        let pending = SharedDataStore.pendingMedicationDoses()
        guard !pending.isEmpty else { return }

        let todaysDoses = repository.todaysDoses()
        for entry in pending {
            guard let dose = todaysDoses.first(where: { $0.medicationID == entry.medicationID && $0.minuteOfDay == entry.minuteOfDay }),
                  dose.isPending else { continue }
            repository.markDoseTaken(dose)
        }
        SharedDataStore.clearPendingMedicationDoses()
    }
}
