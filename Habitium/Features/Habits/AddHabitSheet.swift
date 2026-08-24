//
//  AddHabitSheet.swift
//  Habitium
//

import SwiftUI

struct AddHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: HabitsViewModel

    @State private var name = ""
    @State private var symbolName = "checkmark.circle.fill"
    @State private var kind: HabitKind = .checkbox
    @State private var goalDirection: HabitGoalDirection = .atLeast
    @State private var targetText = ""
    @State private var unit = ""
    @State private var linkedToWorkouts = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Plantillas rápidas") {
                    ForEach(HabitTemplate.all) { template in
                        Button {
                            apply(template)
                        } label: {
                            Label(template.name, systemImage: template.symbolName)
                        }
                    }
                }

                Section("O uno tuyo") {
                    TextField("Nombre", text: $name)
                    Picker("Tipo", selection: $kind) {
                        Text("Sí/No").tag(HabitKind.checkbox)
                        Text("Número con objetivo").tag(HabitKind.numeric)
                    }
                    .pickerStyle(.segmented)

                    if kind == .numeric {
                        Picker("Meta", selection: $goalDirection) {
                            Text("Como máximo").tag(HabitGoalDirection.atMost)
                            Text("Como mínimo").tag(HabitGoalDirection.atLeast)
                        }
                        TextField("Objetivo (número)", text: $targetText)
                            .keyboardType(.decimalPad)
                        TextField("Unidad (ej: h, vasos)", text: $unit)
                    }

                    if kind == .checkbox {
                        Toggle(isOn: $linkedToWorkouts) {
                            Label("Marcar automáticamente al entrenar con el Watch", systemImage: "applewatch")
                        }
                    }
                }
            }
            .navigationTitle("Nuevo hábito")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        viewModel.addHabit(
                            name: name,
                            symbolName: symbolName,
                            kind: kind,
                            targetValue: kind == .numeric ? Double(targetText.replacingOccurrences(of: ",", with: ".")) : nil,
                            goalDirection: goalDirection,
                            unit: unit.isEmpty ? nil : unit,
                            linkedToWorkouts: kind == .checkbox && linkedToWorkouts
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (kind == .numeric && Double(targetText.replacingOccurrences(of: ",", with: ".")) == nil))
                }
            }
        }
    }

    private func apply(_ template: HabitTemplate) {
        name = template.name
        symbolName = template.symbolName
        kind = template.kind
        goalDirection = template.goalDirection
        targetText = template.targetValue.map { String(format: "%g", $0) } ?? ""
        unit = template.unit ?? ""
        linkedToWorkouts = template.linkedToWorkouts
    }
}
