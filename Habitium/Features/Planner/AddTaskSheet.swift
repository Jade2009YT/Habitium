//
//  AddTaskSheet.swift
//  Habitium
//

import SwiftUI

struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: PlannerViewModel

    @State private var title = ""
    @State private var dueDate: Date
    @State private var reminderEnabled = true
    @State private var priority: TaskPriority = .medium

    init(viewModel: PlannerViewModel) {
        self.viewModel = viewModel
        _dueDate = State(initialValue: viewModel.selectedDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título de la tarea", text: $title)
                DatePicker("Fecha límite", selection: $dueDate)
                Toggle("Recordatorio", isOn: $reminderEnabled)
                Picker("Prioridad", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            .navigationTitle("Nueva tarea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        viewModel.addTask(
                            title: title,
                            dueDate: dueDate,
                            reminderDate: reminderEnabled ? dueDate : nil,
                            priority: priority
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
