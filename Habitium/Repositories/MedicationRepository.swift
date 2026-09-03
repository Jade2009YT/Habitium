//
//  MedicationRepository.swift
//  Habitium
//
//  Data-layer abstraction over Medication/MedicationDoseLog persistence,
//  plus the computed "today's doses" view (Medication schedule x today's
//  logs) that HomeView, MedicationView and the medication widget all read.
//

import Foundation
import SwiftData

struct MedicationDose: Identifiable, Equatable {
    var id: String { "\(medicationID)-\(minuteOfDay)" }
    var medicationID: UUID
    var medicationName: String
    var dosage: String?
    var scheduledDate: Date
    var minuteOfDay: Int
    var isTaken: Bool
    var isSkipped: Bool

    var isPending: Bool { !isTaken && !isSkipped }
}

@MainActor
protocol MedicationRepository {
    func medications() -> [Medication]
    func addMedication(name: String, dosage: String?, notes: String?, reminderMinutesSinceMidnight: [Int])
    func deleteMedication(_ medication: Medication)
    func setActive(_ medication: Medication, isActive: Bool)

    /// All scheduled doses for today, in chronological order, with their
    /// taken/skipped/pending status.
    func todaysDoses() -> [MedicationDose]
    /// Soonest pending dose today — nil if everything's taken/skipped or
    /// there are no active medications. Feeds HomeView and the widget.
    func nextPendingDose() -> MedicationDose?

    func markDoseTaken(_ dose: MedicationDose)
    func markDoseSkipped(_ dose: MedicationDose)
}

@MainActor
final class SwiftDataMedicationRepository: MedicationRepository {

    private let context: ModelContext
    private let progression: ProgressionRepository

    init(context: ModelContext, progression: ProgressionRepository) {
        self.context = context
        self.progression = progression
    }

    func medications() -> [Medication] {
        (try? context.fetch(FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func addMedication(name: String, dosage: String?, notes: String?, reminderMinutesSinceMidnight: [Int]) {
        let identifiers = NotificationScheduler.shared.scheduleMedicationReminders(
            medicationName: name,
            dosage: dosage,
            minutesSinceMidnight: reminderMinutesSinceMidnight
        )
        let medication = Medication(
            name: name,
            dosage: dosage,
            notes: notes,
            reminderMinutesSinceMidnight: reminderMinutesSinceMidnight,
            notificationIdentifiers: identifiers
        )
        context.insert(medication)
        save()
        syncWidgetSnapshot()
    }

    func deleteMedication(_ medication: Medication) {
        NotificationScheduler.shared.cancelReminders(identifiers: medication.notificationIdentifiers)
        // Cloud-side dose logs cascade-delete with the medication (see
        // supabase/schema.sql's "on delete cascade") — no separate
        // tombstone needed for those.
        context.insert(PendingCloudDeletion(table: "medications", recordID: medication.id))
        context.delete(medication)
        save()
        syncWidgetSnapshot()
    }

    func setActive(_ medication: Medication, isActive: Bool) {
        medication.isActive = isActive
        if !isActive {
            NotificationScheduler.shared.cancelReminders(identifiers: medication.notificationIdentifiers)
        } else {
            let identifiers = NotificationScheduler.shared.scheduleMedicationReminders(
                medicationName: medication.name,
                dosage: medication.dosage,
                minutesSinceMidnight: medication.reminderMinutesSinceMidnight
            )
            medication.notificationIdentifiers = identifiers
        }
        medication.updatedAt = .now
        save()
        syncWidgetSnapshot()
    }

    func todaysDoses() -> [MedicationDose] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let logs = logs(on: today)

        var doses: [MedicationDose] = []
        for medication in medications() where medication.isActive {
            for minute in medication.reminderMinutesSinceMidnight {
                let log = logs.first { $0.medicationID == medication.id && $0.minuteOfDay == minute }
                let scheduledDate = calendar.date(byAdding: .minute, value: minute, to: today) ?? today
                doses.append(MedicationDose(
                    medicationID: medication.id,
                    medicationName: medication.name,
                    dosage: medication.dosage,
                    scheduledDate: scheduledDate,
                    minuteOfDay: minute,
                    isTaken: log?.takenAt != nil,
                    isSkipped: log?.skipped ?? false
                ))
            }
        }
        return doses.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    func nextPendingDose() -> MedicationDose? {
        todaysDoses().first { $0.isPending }
    }

    func markDoseTaken(_ dose: MedicationDose) {
        upsertLog(for: dose) { log in
            log.takenAt = .now
            log.skipped = false
        }
        syncWidgetSnapshot()
        // La clave identifica la toma exacta (medicamento + hora + día),
        // así que cada toma se premia una vez. Omitir no da nada, a
        // propósito: premiaría saltarse la medicación.
        progression.award(
            .medicationTaken,
            dedupeKey: SwiftDataProgressionRepository.key("dose:\(dose.medicationID):\(dose.minuteOfDay)", on: .now),
            on: .now
        )
    }

    func markDoseSkipped(_ dose: MedicationDose) {
        upsertLog(for: dose) { log in
            log.skipped = true
            log.takenAt = nil
        }
        syncWidgetSnapshot()
    }

    // MARK: - Private

    private func logs(on date: Date) -> [MedicationDoseLog] {
        let range = Calendar.current.dayRange(containing: date)
        let descriptor = FetchDescriptor<MedicationDoseLog>(
            predicate: #Predicate<MedicationDoseLog> { log in
                log.date >= range.lowerBound && log.date < range.upperBound
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func upsertLog(for dose: MedicationDose, mutate: (MedicationDoseLog) -> Void) {
        let today = Calendar.current.startOfDay(for: .now)
        let existing = logs(on: today).first { $0.medicationID == dose.medicationID && $0.minuteOfDay == dose.minuteOfDay }
        let log = existing ?? MedicationDoseLog(medicationID: dose.medicationID, date: today, minuteOfDay: dose.minuteOfDay)
        if existing == nil { context.insert(log) }
        mutate(log)
        log.updatedAt = .now
        save()
    }

    private func save() {
        try? context.save()
    }

    private func syncWidgetSnapshot() {
        let next = nextPendingDose()
        let snapshot = MedicationWidgetSnapshot(
            nextDoseName: next?.medicationName,
            nextDoseDosage: next?.dosage,
            nextDoseTime: next?.scheduledDate,
            nextDoseIdentifier: next.map {
                MedicationWidgetSnapshot.DoseIdentifier(medicationID: $0.medicationID.uuidString, minuteOfDay: $0.minuteOfDay)
            },
            pendingCount: todaysDoses().filter { $0.isPending }.count,
            updatedAt: .now
        )
        SharedDataStore.writeMedicationSnapshot(snapshot)
        WidgetRefresher.reloadMedicationWidget()
        WatchConnectivityBridge.shared.sendCurrentSnapshots()
    }
}
