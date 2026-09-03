//
//  HabitRepository.swift
//  Habitium
//
//  Data-layer abstraction over Habit/HabitLog persistence, plus the
//  computed "today's status" (and per-habit streak) that HabitsView and
//  the Home card read.
//

import Foundation
import SwiftData

struct HabitStatus: Identifiable, Equatable {
    var id: UUID { habitID }
    var habitID: UUID
    var name: String
    var symbolName: String
    var kind: HabitKind
    var targetValue: Double?
    var goalDirection: HabitGoalDirection
    var unit: String?
    var isCompletedToday: Bool
    var valueToday: Double?
    var streak: Int

    /// Whether today already meets the habit's own definition of success —
    /// checked for .checkbox, at/over or at/under target for .numeric.
    var isGoalMetToday: Bool {
        switch kind {
        case .checkbox:
            return isCompletedToday
        case .numeric:
            guard let valueToday, let targetValue else { return false }
            switch goalDirection {
            case .atMost: return valueToday <= targetValue
            case .atLeast: return valueToday >= targetValue
            }
        }
    }
}

@MainActor
protocol HabitRepository {
    func habits() -> [Habit]
    func addHabit(name: String, symbolName: String, kind: HabitKind, targetValue: Double?, goalDirection: HabitGoalDirection, unit: String?, linkedToWorkouts: Bool)
    func deleteHabit(_ habit: Habit)
    func setActive(_ habit: Habit, isActive: Bool)

    func todaysStatuses() -> [HabitStatus]
    func toggleCompleted(_ habit: Habit)
    func logValue(_ habit: Habit, value: Double)
    /// Idempotent, non-toggling completion — used by WorkoutRepository to
    /// auto-complete a linked habit when a Watch workout arrives, where
    /// calling it twice in one day (e.g. two workouts) must not un-complete it.
    func markCompletedToday(_ habit: Habit)
}

@MainActor
final class SwiftDataHabitRepository: HabitRepository {

    private let context: ModelContext
    private let progression: ProgressionRepository

    init(context: ModelContext, progression: ProgressionRepository) {
        self.context = context
        self.progression = progression
    }

    func habits() -> [Habit] {
        (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func addHabit(name: String, symbolName: String, kind: HabitKind, targetValue: Double?, goalDirection: HabitGoalDirection, unit: String?, linkedToWorkouts: Bool = false) {
        let nextOrder = (habits().map(\.sortOrder).max() ?? -1) + 1
        let habit = Habit(
            name: name,
            symbolName: symbolName,
            kind: kind,
            targetValue: targetValue,
            goalDirection: goalDirection,
            unit: unit,
            sortOrder: nextOrder,
            linkedToWorkouts: linkedToWorkouts
        )
        context.insert(habit)
        save()
    }

    func deleteHabit(_ habit: Habit) {
        // Cloud-side habit_logs cascade-delete with the habit (see
        // supabase/schema.sql's "on delete cascade") — no separate
        // tombstone needed for those.
        context.insert(PendingCloudDeletion(table: "habits", recordID: habit.id))
        context.delete(habit)
        save()
    }

    func setActive(_ habit: Habit, isActive: Bool) {
        habit.isActive = isActive
        habit.updatedAt = .now
        save()
    }

    func todaysStatuses() -> [HabitStatus] {
        let today = Calendar.current.startOfDay(for: .now)
        let logs = logs(on: today)

        return habits().filter(\.isActive).map { habit in
            let log = logs.first { $0.habitID == habit.id }
            return HabitStatus(
                habitID: habit.id,
                name: habit.name,
                symbolName: habit.symbolName,
                kind: HabitKind(rawValue: habit.kind) ?? .checkbox,
                targetValue: habit.targetValue,
                goalDirection: HabitGoalDirection(rawValue: habit.goalDirection) ?? .atLeast,
                unit: habit.unit,
                isCompletedToday: log?.isCompleted ?? false,
                valueToday: log?.value,
                streak: streak(for: habit)
            )
        }
    }

    func toggleCompleted(_ habit: Habit) {
        let today = Calendar.current.startOfDay(for: .now)
        let log = existingOrNewLog(for: habit, on: today)
        log.isCompleted.toggle()
        log.updatedAt = .now
        save()
        // Solo se premia al marcar, nunca al desmarcar: quitar XP por
        // corregir un toque haría que la gente evitara tocar la app.
        if log.isCompleted { awardXP(for: habit, on: today) }
    }

    func logValue(_ habit: Habit, value: Double) {
        let today = Calendar.current.startOfDay(for: .now)
        let log = existingOrNewLog(for: habit, on: today)
        log.value = value
        log.isCompleted = true // a logged number counts as "done" for the day, goal met or not
        log.updatedAt = .now
        save()
        awardXP(for: habit, on: today)
    }

    func markCompletedToday(_ habit: Habit) {
        let today = Calendar.current.startOfDay(for: .now)
        let log = existingOrNewLog(for: habit, on: today)
        guard !log.isCompleted else { return } // already done today — no-op, not a toggle
        log.isCompleted = true
        log.updatedAt = .now
        save()
        awardXP(for: habit, on: today)
    }

    /// Experiencia por el hábito y, si con este se cierra el día entero,
    /// la bonificación de "todos los hábitos". Las claves incluyen la
    /// fecha, así que cada cosa se premia una vez al día como mucho.
    private func awardXP(for habit: Habit, on day: Date) {
        progression.award(
            .habitCompleted,
            dedupeKey: SwiftDataProgressionRepository.key("habit:\(habit.id)", on: day),
            on: day
        )

        let statuses = todaysStatuses()
        if !statuses.isEmpty && statuses.allSatisfy(\.isGoalMetToday) {
            progression.award(
                .allHabitsCompleted,
                dedupeKey: SwiftDataProgressionRepository.key("all-habits", on: day),
                on: day
            )
        }
    }

    // MARK: - Private

    private func logs(on date: Date) -> [HabitLog] {
        let range = Calendar.current.dayRange(containing: date)
        let descriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate<HabitLog> { log in
                log.date >= range.lowerBound && log.date < range.upperBound
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func existingOrNewLog(for habit: Habit, on date: Date) -> HabitLog {
        if let existing = logs(on: date).first(where: { $0.habitID == habit.id }) {
            return existing
        }
        let log = HabitLog(habitID: habit.id, date: date)
        context.insert(log)
        return log
    }

    /// Consecutive days (including today, if already logged) this habit's
    /// goal was met — same backward-walk approach as
    /// CalculateLoggingStreakUseCase, just scoped to one habit and
    /// evaluated against its own goal instead of "any entry exists".
    private func streak(for habit: Habit) -> Int {
        // Pull the id out first: inside #Predicate, `habit.id` on a
        // @Model reads as part of the query (a key path into another
        // model) rather than as a captured constant, which doesn't
        // type-check. A plain local UUID does.
        let habitID = habit.id
        let allLogsDescriptor = FetchDescriptor<HabitLog>(
            predicate: #Predicate<HabitLog> { $0.habitID == habitID }
        )
        let allLogs = (try? context.fetch(allLogsDescriptor)) ?? []
        let calendar = Calendar.current
        let logsByDay = Dictionary(uniqueKeysWithValues: allLogs.map { (calendar.startOfDay(for: $0.date), $0) })

        let kind = HabitKind(rawValue: habit.kind) ?? .checkbox
        let direction = HabitGoalDirection(rawValue: habit.goalDirection) ?? .atLeast

        func goalMet(_ log: HabitLog?) -> Bool {
            guard let log else { return false }
            switch kind {
            case .checkbox: return log.isCompleted
            case .numeric:
                guard let value = log.value, let target = habit.targetValue else { return false }
                return direction == .atMost ? value <= target : value >= target
            }
        }

        var cursor = calendar.startOfDay(for: .now)
        if !goalMet(logsByDay[cursor]) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var streak = 0
        while goalMet(logsByDay[cursor]) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func save() {
        try? context.save()
    }
}
