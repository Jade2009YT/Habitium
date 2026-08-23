//
//  MedicationView.swift
//  Habitium
//
//  Reachable from HomeView's medication card — not a 5th tab, same
//  pattern as SettingsView. Shows today's doses (take/skip) plus the list
//  of configured medications.
//

import SwiftUI

struct MedicationView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: MedicationViewModel?
    @State private var showingAddMedication = false

    var body: some View {
        Group {
            if let viewModel {
                List {
                    Section("Hoy") {
                        if viewModel.todaysDoses.isEmpty {
                            Text("No tienes tomas programadas hoy.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.todaysDoses) { dose in
                                doseRow(dose, viewModel: viewModel)
                            }
                        }
                    }

                    Section("Tus medicamentos") {
                        if viewModel.medications.isEmpty {
                            Text("Aún no has añadido ninguno.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.medications) { medication in
                                medicationRow(medication, viewModel: viewModel)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Medicación")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMedication = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddMedication, onDismiss: { viewModel?.refresh() }) {
            if let viewModel { AddMedicationSheet(viewModel: viewModel) }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MedicationViewModel(container: container)
            } else {
                viewModel?.refresh()
            }
        }
    }

    private func doseRow(_ dose: MedicationDose, viewModel: MedicationViewModel) -> some View {
        HStack {
            Image(systemName: "pills.fill")
                .foregroundStyle(dose.isTaken ? .green : (dose.isSkipped ? .secondary : .orange))
            VStack(alignment: .leading) {
                Text(dose.medicationName)
                    .font(.subheadline.bold())
                    .strikethrough(dose.isSkipped)
                Text([dose.dosage, dose.scheduledDate.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if dose.isPending {
                Button("Tomada") { viewModel.markTaken(dose) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Omitir") { viewModel.markSkipped(dose) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if dose.isTaken {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("Omitida").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func medicationRow(_ medication: Medication, viewModel: MedicationViewModel) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(medication.name).font(.subheadline.bold())
                Text(scheduleDescription(medication))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { medication.isActive },
                set: { viewModel.setActive(medication, isActive: $0) }
            ))
            .labelsHidden()
        }
        .swipeActions {
            Button(role: .destructive) {
                viewModel.deleteMedication(medication)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private func scheduleDescription(_ medication: Medication) -> String {
        let times = medication.reminderMinutesSinceMidnight.map { minute -> String in
            String(format: "%02d:%02d", minute / 60, minute % 60)
        }
        var parts = [times.joined(separator: ", ")]
        if let dosage = medication.dosage { parts.insert(dosage, at: 0) }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        MedicationView()
            .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
    }
}
