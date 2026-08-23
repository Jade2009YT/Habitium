//
//  MarkDoseTakenIntent.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Interactive-widget button on the medication widget: marks a dose taken
//  WITHOUT opening the app, same pattern as CompleteTaskIntent — updates
//  the shared snapshot optimistically and queues the real write for the
//  app to apply to SwiftData next time it's active.
//

import AppIntents
import WidgetKit

struct MarkDoseTakenIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar toma"
    static var description = IntentDescription("Marca la toma de medicación como hecha.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "ID del medicamento")
    var medicationID: String
    @Parameter(title: "Minuto del día")
    var minuteOfDay: Int

    init() {
        self.medicationID = ""
        self.minuteOfDay = 0
    }

    init(medicationID: String, minuteOfDay: Int) {
        self.medicationID = medicationID
        self.minuteOfDay = minuteOfDay
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: medicationID) else { return .result() }

        SharedDataStore.queueMedicationDoseTaken(medicationID: uuid, minuteOfDay: minuteOfDay)

        var snapshot = SharedDataStore.readMedicationSnapshot()
        // Optimistic: if this was the dose the widget was showing as
        // "next", clear it — the app will recompute the real next dose
        // and push a fresh snapshot next time it's active.
        if snapshot.nextDoseTime != nil {
            snapshot.pendingCount = max(0, snapshot.pendingCount - 1)
            if snapshot.pendingCount == 0 {
                snapshot.nextDoseName = nil
                snapshot.nextDoseDosage = nil
                snapshot.nextDoseTime = nil
            }
        }
        SharedDataStore.writeMedicationSnapshot(snapshot)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.medication)
        return .result()
    }
}
