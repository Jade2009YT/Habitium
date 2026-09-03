//
//  HabitsView.swift
//  Habitium
//
//  Accesible desde la tarjeta "Hábitos" de Inicio — no es una pestaña,
//  mismo patrón que Ajustes/Medicación. Arriba, el resumen del día con
//  la racha más larga; debajo, los hábitos de hoy y la gestión de la
//  lista.
//

import SwiftUI

struct HabitsView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: HabitsViewModel?
    @State private var showingAddHabit = false

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    summaryCard(viewModel)
                    todayCard(viewModel)
                    if !viewModel.habits.isEmpty {
                        manageCard(viewModel)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .themedBackground()
        .navigationTitle("Hábitos")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Resumen

    private func summaryCard(_ viewModel: HabitsViewModel) -> some View {
        let statuses = viewModel.todaysStatuses
        let met = statuses.filter(\.isGoalMetToday).count
        let best = statuses.map(\.streak).max() ?? 0

        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(met)")
                    .font(Theme.Fonts.metric)
                    .foregroundStyle(Theme.Colors.habits)
                    .contentTransition(.numericText())
                Text("de \(statuses.count) hoy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if best > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        StreakBadge(days: best)
                        Text("mejor racha")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ProgressBar(
                value: statuses.isEmpty ? 0 : Double(met) / Double(statuses.count),
                color: Theme.Colors.habits,
                height: 9
            )

            if !statuses.isEmpty && met == statuses.count {
                Text("Día completo. 🎉")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Colors.habits)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    // MARK: - Hoy

    private func todayCard(_ viewModel: HabitsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Hoy", symbol: "repeat.circle.fill", color: Theme.Colors.habits)

            if viewModel.todaysStatuses.isEmpty {
                EmptyHint(symbol: "plus.circle", message: "Aún no tienes hábitos. Añade uno con el +.")
            } else {
                ForEach(Array(viewModel.todaysStatuses.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { Divider() }
                    HabitRow(status: status, viewModel: viewModel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Gestión

    private func manageCard(_ viewModel: HabitsViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Tus hábitos", symbol: "slider.horizontal.3", color: .secondary)

            ForEach(Array(viewModel.habits.enumerated()), id: \.element.id) { index, habit in
                if index > 0 { Divider() }
                HStack(spacing: 11) {
                    IconBadge(
                        symbol: habit.symbolName,
                        color: habit.isActive ? Theme.Colors.habits : .secondary,
                        size: 26
                    )
                    Text(habit.name)
                        .font(.subheadline)
                        .foregroundStyle(habit.isActive ? .primary : .secondary)
                    if habit.linkedToWorkouts {
                        Image(systemName: "applewatch")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.habits)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { habit.isActive },
                        set: { viewModel.setActive(habit, isActive: $0) }
                    ))
                    .labelsHidden()
                    .tint(Theme.Colors.habits)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.deleteHabit(habit)
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
            }

            Text("Desactiva un hábito para dejar de verlo hoy sin perder su historial. Mantén pulsado para eliminarlo del todo.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Fila de hábito

private struct HabitRow: View {
    let status: HabitStatus
    var viewModel: HabitsViewModel

    @State private var valueText: String = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: status.symbolName,
                color: status.isGoalMetToday ? Theme.Colors.habits : .secondary
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(status.name).font(Theme.Fonts.rowTitle)
                HStack(spacing: 6) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if status.streak > 0 {
                        StreakBadge(days: status.streak)
                    }
                }
            }

            Spacer(minLength: 4)

            switch status.kind {
            case .checkbox:
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                        viewModel.toggleCompleted(status)
                    }
                } label: {
                    Image(systemName: status.isCompletedToday ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(status.isCompletedToday ? Theme.Colors.habits : .secondary)
                        // El rebote al marcar: pequeño, pero es lo que
                        // hace que apetezca marcar el siguiente.
                        .scaleEffect(status.isCompletedToday ? 1.12 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: status.isCompletedToday)
                }
                .buttonStyle(.plain)

            case .numeric:
                HStack(spacing: 6) {
                    TextField("0", text: $valueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .focused($isEditing)
                    if let unit = status.unit {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .onChange(of: isEditing) { _, editing in
            // Se guarda al salir del campo en vez de con un botón "OK":
            // un botón más por fila hacía la lista muy ruidosa.
            guard !editing else { return }
            commitValue()
        }
        .onAppear {
            if valueText.isEmpty, let value = status.valueToday {
                valueText = formatted(value)
            }
        }
    }

    private var subtitle: String? {
        guard status.kind == .numeric, let target = status.targetValue else { return nil }
        let direction = status.goalDirection == .atMost ? "máx." : "mín."
        return "\(direction) \(formatted(target))\(status.unit.map { " \($0)" } ?? "")"
    }

    private func commitValue() {
        let normalized = valueText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return }
        viewModel.logValue(status, value: value)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}

#Preview {
    NavigationStack {
        HabitsView()
            .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
    }
}
