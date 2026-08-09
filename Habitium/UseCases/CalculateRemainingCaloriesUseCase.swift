//
//  CalculateRemainingCaloriesUseCase.swift
//  Habitium
//
//  Domain-layer calculation shared by HomeView and FoodTrackerView so the
//  "remaining calories today" number is computed in exactly one place.
//

import Foundation

struct NutritionDailyProgress: Equatable {
    var consumedCalories: Double
    var goalCalories: Double
    var consumedMacros: Macronutrients
    var goalMacros: Macronutrients

    var remainingCalories: Double { max(0, goalCalories - consumedCalories) }
    var progress: Double { goalCalories > 0 ? min(consumedCalories / goalCalories, 1.0) : 0 }
    var isOverGoal: Bool { consumedCalories > goalCalories }
}

@MainActor
struct CalculateRemainingCaloriesUseCase {
    let repository: NutritionRepository

    func execute(for date: Date = .now) -> NutritionDailyProgress {
        let entries = repository.entries(on: date)
        let goal = repository.currentGoal()

        let consumed = entries.reduce(0) { $0 + $1.calories }
        let macros = Macronutrients(
            proteinGrams: entries.reduce(0) { $0 + $1.proteinGrams },
            carbsGrams: entries.reduce(0) { $0 + $1.carbsGrams },
            fatGrams: entries.reduce(0) { $0 + $1.fatGrams }
        )

        return NutritionDailyProgress(
            consumedCalories: consumed,
            goalCalories: goal.dailyCalorieGoal,
            consumedMacros: macros,
            goalMacros: Macronutrients(
                proteinGrams: goal.proteinGoalGrams,
                carbsGrams: goal.carbsGoalGrams,
                fatGrams: goal.fatGoalGrams
            )
        )
    }
}
