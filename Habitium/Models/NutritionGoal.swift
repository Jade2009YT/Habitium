//
//  NutritionGoal.swift
//  Habitium
//
//  Configurable daily targets used to compute progress bars in
//  FoodTrackerView, HomeView and the nutrition widget. A single row is
//  kept (enforced by the repository), so users can retune goals without
//  losing history.
//
//  targetWeightKg/weeklyRateKg are optional — only needed if the user
//  wants Habitium to *suggest* calorie-goal adjustments based on their
//  real weight trend (PlateLens-style adaptive coaching). Leaving them nil
//  keeps the goal purely manual, same as before.
//
//  weeklyRateKg: desired weight change per week — negative to lose,
//  positive to gain, 0 (or nil) to maintain.
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
    var targetWeightKg: Double?
    var weeklyRateKg: Double?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dailyCalorieGoal: Double = 2000,
        proteinGoalGrams: Double = 120,
        carbsGoalGrams: Double = 225,
        fatGoalGrams: Double = 65,
        targetWeightKg: Double? = nil,
        weeklyRateKg: Double? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.dailyCalorieGoal = dailyCalorieGoal
        self.proteinGoalGrams = proteinGoalGrams
        self.carbsGoalGrams = carbsGoalGrams
        self.fatGoalGrams = fatGoalGrams
        self.targetWeightKg = targetWeightKg
        self.weeklyRateKg = weeklyRateKg
        self.updatedAt = updatedAt
    }
}
