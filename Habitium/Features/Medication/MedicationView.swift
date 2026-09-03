//
//  MedicationView.swift
//  Habitium
//
//  Accesible desde la tarjeta "Medicación" de Inicio — no es una quinta
//  pestaña, mismo patrón que Ajustes/Hábitos. Arriba, el progreso de
//  tomas del día; debajo, cada toma (tomar/omitir) y la lista de
//  medicamentos configurados.
//

import SwiftUI

struct MedicationView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: MedicationViewModel?
    @State private var showingAddMedication = false

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    if !viewModel.todaysDoses.isEmpty {
                        summaryCard(viewModel)
                    }
                    dosesCard(viewModel)
                    medicationsCard(viewModel)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .background(Theme.Colors.screenBackground)
        .navigationTitle("Medicación")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Resumen del día

    private func summaryCard(_ viewModel: MedicationViewModel) -> some View {
        let doses = viewModel.todaysDoses
        let taken = doses.filter(\.isTaken).count
        let pending = doses.filter(\.isPending).count

        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(taken)")
                    .font(Theme.Fonts.metric)
                    .foregroundStyle(Theme.Colors.medication)
                    .contentTransition(.numericText())
                Text("de \(doses.count) tomas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pending == 0 ? "Todo al día" : "\(pending) pendiente\(pending == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pending == 0 ? Theme.Colors.nutrition : Theme.Colors.medication)
            }

            ProgressBar(
                value: doses.isEmpty ? 0 : Double(taken) / Double(doses.count),
                color: Theme.Colors.medication,
                height: 9
            )
        }
        .cardStyle()
    }

    // MARK: - Tomas de hoy

    private func dosesCard(_ viewModel: MedicationViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Hoy", symbol: "clock.fill", color: Theme.Colors.medication)

            if viewModel.todaysDoses.isEmpty {
                EmptyHint(symbol: "plus.circle", message: "No tienes tomas programadas hoy.")
            } else {
                ForEach(Array(viewModel.todaysDoses.enumerated()), id: \.element.id) { index, dose in
                    if index > 0 { Divider() }
                    doseRow(dose, viewModel: viewModel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func doseRow(_ dose: MedicationDose, viewModel: MedicationViewModel) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "pills.fill", color: doseColor(dose))

            VStack(alignment: .leading, spacing: 2) {
                Text(dose.medicationName)
                    .font(Theme.Fonts.rowTitle)
                    .strikethrough(dose.isSkipped)
                    .foregroundStyle(dose.isPending ? .primary : .secondary)
                Text(subtitle(for: dose))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if dose.isPending {
                // Dos acciones distintas ("tomada" no es lo mismo que
                // "omitida" en un historial de medicación), así que se
                // mantienen separadas en vez de un único interruptor.
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) {
                        viewModel.markTaken(dose)
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.Colors.medication, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.markSkipped(dose)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
            } else if dose.isTaken {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.nutrition)
            } else {
                Text("Omitida")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func doseColor(_ dose: MedicationDose) -> Color {
        if dose.isTaken { return Theme.Colors.nutrition }
        if dose.isSkipped { return .secondary }
        return Theme.Colors.medication
    }

    private func subtitle(for dose: MedicationDose) -> String {
        [dose.dosage, dose.scheduledDate.formatted(date: .omitted, time: .shortened)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Medicamentos

    private func medicationsCard(_ viewModel: MedicationViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Tus medicamentos", symbol: "list.bullet", color: .secondary)

            if viewModel.medications.isEmpty {
                EmptyHint(symbol: "plus.circle", message: "Aún no has añadido ninguno.")
            } else {
                ForEach(Array(viewModel.medications.enumerated()), id: \.element.id) { index, medication in
                    if index > 0 { Divider() }
                    HStack(spacing: 11) {
                        IconBadge(
                            symbol: "pills.fill",
                            color: medication.isActive ? Theme.Colors.medication : .secondary,
                            size: 26
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(medication.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(medication.isActive ? .primary : .secondary)
                            Text(scheduleDescription(medication))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(
                            get: { medication.isActive },
                            set: { viewModel.setActive(medication, isActive: $0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.Colors.medication)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.deleteMedication(medication)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                }

                Text("Desactiva un medicamento para pausar sus recordatorios sin perder el historial. Mantén pulsado para eliminarlo.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func scheduleDescription(_ medication: Medication) -> String {
        let times = medication.reminderMinutesSinceMidnight.map { minute in
            String(format: "%02d:%02d", minute / 60, minute % 60)
        }
        var parts = [times.joined(separator: " · ")]
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
