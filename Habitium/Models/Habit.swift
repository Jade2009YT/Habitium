//
//  Habit.swift
//  Habitium
//
//  A self-tracked daily habit — anything from "menos de 3h de pantalla"
//  to "beber agua" to "hacer ejercicio". Deliberately manual: logging
//  real Screen Time automatically would need Apple's restricted Family
//  Controls entitlement (needs Apple's approval, likely a paid developer
//  account) — see README. This works today with zero extra permissions:
//  you look at the number iOS already shows you in Settings > Screen
//  Time and log it here, same as any other habit.
//

import Foundation
import SwiftData

enum HabitKind: String, Codable, CaseIterable {
    /// Simple did-it/didn't-it (exercise, read, meditate...).
    case checkbox
    /// A number logged against a target (screen time hours, glasses of
    /// water, hours slept...).
    case numeric
}

enum HabitGoalDirection: String, Codable, CaseIterable {
    /// Meeting the goal means staying AT OR UNDER the target — screen
    /// time, sugar, money spent.
    case atMost
    /// Meeting the goal means reaching AT LEAST the target — water,
    /// steps, hours slept.
    case atLeast
}

@Model
final class Habit {
    var id: UUID
    var name: String
    var symbolName: String
    var kind: HabitKind.RawValue
    /// Only meaningful for .numeric habits.
    var targetValue: Double?
    var goalDirection: HabitGoalDirection.RawValue
    /// Unit label for numeric habits, e.g. "h", "vasos".
    var unit: String?
    var isActive: Bool
    var sortOrder: Int
    var createdAt: Date
    /// When true, finishing an Apple Watch workout (see WorkoutRepository)
    /// automatically marks this habit done for today — no manual check-off
    /// needed for something the Watch already knows happened. Only
    /// meaningful for .checkbox habits (e.g. "Hacer ejercicio").
    var linkedToWorkouts: Bool
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbolName: String,
        kind: HabitKind,
        targetValue: Double? = nil,
        goalDirection: HabitGoalDirection = .atLeast,
        unit: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        linkedToWorkouts: Bool = false,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.kind = kind.rawValue
        self.targetValue = targetValue
        self.goalDirection = goalDirection.rawValue
        self.unit = unit
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.linkedToWorkouts = linkedToWorkouts
        self.updatedAt = updatedAt
    }
}

/// One day's entry for one habit — completion (checkbox) or a logged
/// number (numeric).
@Model
final class HabitLog {
    var id: UUID
    var habitID: UUID
    var date: Date
    var isCompleted: Bool
    var value: Double?
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(id: UUID = UUID(), habitID: UUID, date: Date, isCompleted: Bool = false, value: Double? = nil, updatedAt: Date = .now) {
        self.id = id
        self.habitID = habitID
        self.date = date
        self.isCompleted = isCompleted
        self.value = value
        self.updatedAt = updatedAt
    }
}
