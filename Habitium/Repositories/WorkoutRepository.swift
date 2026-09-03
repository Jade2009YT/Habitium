//
//  WorkoutRepository.swift
//  Habitium
//
//  Receives sets logged on the Apple Watch (LoggedWorkoutSet, over
//  WatchConnectivity — see WatchConnectivityBridge.onWorkoutSetsReceived)
//  and persists them as WorkoutSet rows. Also the one place that knows
//  about the Habit <-> workout link: any habit with `linkedToWorkouts`
//  gets auto-completed for today the moment a set arrives, so "Hacer
//  ejercicio" ticks itself off without a manual check from the wrist.
//

import Foundation
import SwiftData

@MainActor
protocol WorkoutRepository {
    func save(_ sets: [LoggedWorkoutSet])
    func recentSets(limit: Int) -> [WorkoutSet]
}

@MainActor
final class SwiftDataWorkoutRepository: WorkoutRepository {

    private let context: ModelContext
    private let habitRepository: HabitRepository
    private let progression: ProgressionRepository

    init(context: ModelContext, habitRepository: HabitRepository, progression: ProgressionRepository) {
        self.context = context
        self.habitRepository = habitRepository
        self.progression = progression
    }

    func save(_ sets: [LoggedWorkoutSet]) {
        guard !sets.isEmpty else { return }

        // Dedupe by id: transferUserInfo is at-least-once delivery, and a
        // retried delivery (e.g. after the iPhone was unreachable) must not
        // double-insert the same sets.
        let existingIDs = Set((try? context.fetch(FetchDescriptor<WorkoutSet>()))?.map(\.id) ?? [])
        var insertedAny = false
        for set in sets where !existingIDs.contains(set.id) {
            context.insert(WorkoutSet(id: set.id, exerciseName: set.exerciseName, reps: set.reps, date: set.date))
            insertedAny = true
        }
        guard insertedAny else { return }
        try? context.save()

        for habit in habitRepository.habits() where habit.linkedToWorkouts && habit.isActive {
            habitRepository.markCompletedToday(habit)
        }

        // Un entrenamiento al día, no una serie: si diera por serie,
        // lo óptimo sería trocear el entreno en veinte series de una.
        let day = sets.first?.date ?? .now
        progression.award(
            .workoutLogged,
            dedupeKey: SwiftDataProgressionRepository.key("workout", on: day),
            on: day
        )
    }

    func recentSets(limit: Int = 20) -> [WorkoutSet] {
        var descriptor = FetchDescriptor<WorkoutSet>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
