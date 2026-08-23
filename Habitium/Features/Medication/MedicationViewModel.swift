//
//  MedicationViewModel.swift
//  Habitium
//
//  Drives MedicationView: today's doses (with take/skip actions) and the
//  list of configured medications.
//

import Foundation
import Observation

@MainActor
@Observable
final class MedicationViewModel {

    private(set) var todaysDoses: [MedicationDose] = []
    private(set) var medications: [Medication] = []

    private let container: AppDependencyContainer
    private var repository: MedicationRepository { container.medicationRepository }

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        todaysDoses = repository.todaysDoses()
        medications = repository.medications()
    }

    func markTaken(_ dose: MedicationDose) {
        repository.markDoseTaken(dose)
        refresh()
    }

    func markSkipped(_ dose: MedicationDose) {
        repository.markDoseSkipped(dose)
        refresh()
    }

    func addMedication(name: String, dosage: String?, notes: String?, reminderMinutesSinceMidnight: [Int]) {
        repository.addMedication(name: name, dosage: dosage, notes: notes, reminderMinutesSinceMidnight: reminderMinutesSinceMidnight)
        refresh()
    }

    func deleteMedication(_ medication: Medication) {
        repository.deleteMedication(medication)
        refresh()
    }

    func setActive(_ medication: Medication, isActive: Bool) {
        repository.setActive(medication, isActive: isActive)
        refresh()
    }
}
