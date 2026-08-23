//
//  AddMedicationSheet.swift
//  Habitium
//

import SwiftUI

struct AddMedicationSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: MedicationViewModel

    @State private var name = ""
    @State private var dosage = ""
    @State private var notes = ""
    @State private var times: [Date] = [Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now]

    var body: some View {
        NavigationStack {
            Form {
                Section("Medicamento") {
                    TextField("Nombre (ej: Ibuprofeno)", text: $name)
                    TextField("Dosis (ej: 400 mg)", text: $dosage)
                    TextField("Notas (opcional)", text: $notes, axis: .vertical)
                }

                Section("Horarios de recordatorio") {
                    ForEach(times.indices, id: \.self) { index in
                        HStack {
                            DatePicker("Toma \(index + 1)", selection: $times[index], displayedComponents: .hourAndMinute)
                            if times.count > 1 {
                                Button(role: .destructive) {
                                    times.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        times.append(.now)
                    } label: {
                        Label("Añadir otro horario", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Nueva medicación")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let minutes = times.map { date -> Int in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                            return (components.hour ?? 9) * 60 + (components.minute ?? 0)
                        }
                        viewModel.addMedication(
                            name: name,
                            dosage: dosage.isEmpty ? nil : dosage,
                            notes: notes.isEmpty ? nil : notes,
                            reminderMinutesSinceMidnight: minutes
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || times.isEmpty)
                }
            }
        }
    }
}
