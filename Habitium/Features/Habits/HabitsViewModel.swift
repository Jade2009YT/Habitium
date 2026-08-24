//
//  HabitsViewModel.swift
//  Habitium
//
//  Drives HabitsView: today's status for every active habit, plus habit
//  management (add/delete/activate).
//

import Foundation
import Observation

@MainActor
@Observable
final class HabitsViewModel {

    private(set) var todaysStatuses: [HabitStatus] = []
    private(set) var habits: [Habit] = []

    private let container: AppDependencyContainer
    private var repository: HabitRepository { container.habitRepository }

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        todaysStatuses = repository.todaysStatuses()
        habits = repository.habits()
    }

    func toggleCompleted(_ status: HabitStatus) {
        guard let habit = habits.first(where: { $0.id == status.habitID }) else { return }
        repository.toggleCompleted(habit)
        refresh()
    }

    func logValue(_ status: HabitStatus, value: Double) {
        guard let habit = habits.first(where: { $0.id == status.habitID }) else { return }
        repository.logValue(habit, value: value)
        refresh()
    }

    func addHabit(name: String, symbolName: String, kind: HabitKind, targetValue: Double?, goalDirection: HabitGoalDirection, unit: String?) {
        repository.addHabit(name: name, symbolName: symbolName, kind: kind, targetValue: targetValue, goalDirection: goalDirection, unit: unit)
        refresh()
    }

    func deleteHabit(_ habit: Habit) {
        repository.deleteHabit(habit)
        refresh()
    }

    func setActive(_ habit: Habit, isActive: Bool) {
        repository.setActive(habit, isActive: isActive)
        refresh()
    }
}
