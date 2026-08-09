//
//  AnalyzeMealUseCase.swift
//  Habitium
//
//  Domain-layer use case: turns a photo or text description into a saved
//  FoodEntry by calling the configured AI provider and persisting the
//  result through NutritionRepository. Kept separate from
//  FoodTrackerViewModel so the analysis flow is unit-testable without
//  SwiftUI.
//

import Foundation

@MainActor
struct AnalyzeMealUseCase {
    let analyzer: FoodVisionAnalyzing
    let repository: NutritionRepository

    @discardableResult
    func executeWithPhoto(imageData: Data, mealType: MealType, additionalContext: String? = nil, analyzedBy: String) async throws -> FoodEntry {
        let result = try await analyzer.analyzeMeal(imageData: imageData, additionalContext: additionalContext)
        return persist(result, mealType: mealType, source: .photo, imageData: imageData, analyzedBy: analyzedBy)
    }

    @discardableResult
    func executeWithDescription(_ description: String, mealType: MealType, analyzedBy: String) async throws -> FoodEntry {
        let result = try await analyzer.analyzeMeal(description: description)
        return persist(result, mealType: mealType, source: .text, imageData: nil, analyzedBy: analyzedBy)
    }

    private func persist(_ result: FoodAnalysisResult, mealType: MealType, source: MealSource, imageData: Data?, analyzedBy: String) -> FoodEntry {
        let entry = FoodEntry(
            name: result.mealName,
            mealType: mealType,
            source: source,
            calories: result.calories,
            proteinGrams: result.macros.proteinGrams,
            carbsGrams: result.macros.carbsGrams,
            fatGrams: result.macros.fatGrams,
            imageData: imageData,
            notes: result.confidenceNote,
            analyzedBy: analyzedBy
        )
        repository.addEntry(entry)
        return entry
    }
}
