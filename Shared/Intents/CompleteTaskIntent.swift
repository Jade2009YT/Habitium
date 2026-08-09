//
//  CompleteTaskIntent.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Interactive-widget button on the calendar widget: marks the next task
//  complete WITHOUT opening the app (openAppWhenRun = false). Since the
//  widget extension can't reach the SwiftData store's model types, this
//  optimistically removes the item from the shared snapshot (so the
//  widget updates immediately) and queues the real completion for the app
//  to apply to SwiftData next time it's active — see PendingActionProcessor.
//

import AppIntents
import WidgetKit

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Completar tarea"
    static var description = IntentDescription("Marca la tarea como completada.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "ID de la tarea")
    var taskID: String

    init() {
        self.taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: taskID) else { return .result() }

        SharedDataStore.queueTaskCompletion(id: uuid)

        var snapshot = SharedDataStore.readCalendarSnapshot()
        snapshot.items.removeAll { $0.id == uuid }
        SharedDataStore.writeCalendarSnapshot(snapshot)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calendar)
        return .result()
    }
}
