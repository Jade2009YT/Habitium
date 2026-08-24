//
//  HabitsView.swift
//  Habitium
//
//  Reachable from HomeView's "Hábitos" card — not a 5th tab, same pattern
//  as Ajustes/Medicación. Today's habits (check off or log a number) plus
//  management of the habit list itself.
//

import SwiftUI

struct HabitsView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: HabitsViewModel?
    @State private var showingAddHabit = false

    var body: some View {
        Group {
            if let viewModel {
                List {
                    Section("Hoy") {
                        if viewModel.todaysStatuses.isEmpty {
                            Text("Aún no tienes hábitos. Añade uno con el +.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.todaysStatuses) { status in
                                HabitRow(status: status, viewModel: viewModel)
                            }
                        }
                    }

                    if !viewModel.habits.isEmpty {
                        Section("Tus hábitos") {
                            ForEach(viewModel.habits) { habit in
                                HStack {
                                    Label(habit.name, systemImage: habit.symbolName)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { habit.isActive },
                                        set: { viewModel.setActive(habit, isActive: $0) }
                                    ))
                                    .labelsHidden()
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        viewModel.deleteHabit(habit)
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Hábitos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddHabit = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAddHabit, onDismiss: { viewModel?.refresh() }) {
            if let viewModel { AddHabitSheet(viewModel: viewModel) }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HabitsViewModel(container: container)
            } else {
                viewModel?.refresh()
            }
        }
    }
}

private struct HabitRow: View {
    let status: HabitStatus
    var viewModel: HabitsViewModel

    @State private var valueText: String = ""

    var body: some View {
        HStack {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.isGoalMetToday ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.name).font(.subheadline.bold())
                if status.streak > 0 {
                    Label("\(status.streak) días", systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            switch status.kind {
            case .checkbox:
                Button {
                    viewModel.toggleCompleted(status)
                } label: {
                    Image(systemName: status.isCompletedToday ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(status.isCompletedToday ? .green : .secondary)
                }
                .buttonStyle(.plain)

            case .numeric:
                HStack(spacing: 4) {
                    TextField(status.unit ?? "", text: $valueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .textFieldStyle(.roundedBorder)
                    if let unit = status.unit {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("OK") {
                        guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")) else { return }
                        viewModel.logValue(status, value: value)
                    }
                    .font(.caption.bold())
                }
            }
        }
        .onAppear {
            if valueText.isEmpty, let value = status.valueToday {
                valueText = String(format: "%g", value)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HabitsView()
            .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
    }
}
