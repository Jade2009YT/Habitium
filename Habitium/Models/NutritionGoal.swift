//
//  NutritionGoal.swift
//  Habitium
//
//  Configurable daily targets used to compute progress bars in
//  FoodTrackerView, HomeView and the nutrition widget. A single row is
//  kept (enforced by the repository), so users can retune goals without
//  losing history.
//

import Foundation
import SwiftData

@Model
final class NutritionGoal {
    var id: UUID
    var dailyCalorieGoal: Double
    var proteinGoalGrams: Double
    var carbsGoalGrams: Double
    var fatGoalGrams: Double
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dailyCalorieGoal: Double = 2000,
        proteinGoalGrams: Double = 120,
        carbsGoalGrams: Double = 225,
        fatGoalGrams: Double = 65,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.dailyCalorieGoal = dailyCalorieGoal
        self.proteinGoalGrams = proteinGoalGrams
        self.carbsGoalGrams = carbsGoalGrams
        self.fatGoalGrams = fatGoalGrams
        self.updatedAt = updatedAt
    }
}
