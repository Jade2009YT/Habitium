//
//  AddEventSheet.swift
//  Habitium
//

import SwiftUI

struct AddEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: PlannerViewModel

    @State private var title = ""
    @State private var location = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var reminderEnabled = true

    init(viewModel: PlannerViewModel) {
        self.viewModel = viewModel
        let start = viewModel.selectedDate
        _startDate = State(initialValue: start)
        _endDate = State(initialValue: start.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título del evento", text: $title)
                TextField("Ubicación (opcional)", text: $location)
                DatePicker("Inicio", selection: $startDate)
                DatePicker("Fin", selection: $endDate)
                Toggle("Recordatorio", isOn: $reminderEnabled)
            }
            .navigationTitle("Nuevo evento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        viewModel.addEvent(
                            title: title,
                            startDate: startDate,
                            endDate: endDate,
                            location: location.isEmpty ? nil : location,
                            reminder: reminderEnabled
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
