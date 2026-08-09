//
//  FoodTrackerViewModel.swift
//  Habitium
//
//  Drives FoodTrackerView: today's logged meals, daily progress, and the
//  async AI-analysis flow (photo or text) via AnalyzeMealUseCase.
//

import Foundation
import Observation

@MainActor
@Observable
final class FoodTrackerViewModel {

    private(set) var todayEntries: [FoodEntry] = []
    private(set) var progress: NutritionDailyProgress = .init(
        consumedCalories: 0, goalCalories: 2000, consumedMacros: .zero, goalMacros: .zero
    )
    var isAnalyzing = false
    var errorMessage: String?

    private let container: AppDependencyContainer

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        todayEntries = container.nutritionRepository.entries(on: .now)
        progress = container.makeCalculateRemainingCaloriesUseCase().execute()
    }

    func analyzePhoto(_ imageData: Data, mealType: MealType, context: String? = nil) async {
        await runAnalysis {
            let provider = self.currentProvider()
            try await self.container.makeAnalyzeMealUseCase(provider: provider)
                .executeWithPhoto(imageData: imageData, mealType: mealType, additionalContext: context, analyzedBy: provider.rawValue)
        }
    }

    func analyzeDescription(_ text: String, mealType: MealType) async {
        await runAnalysis {
            let provider = self.currentProvider()
            try await self.container.makeAnalyzeMealUseCase(provider: provider)
                .executeWithDescription(text, mealType: mealType, analyzedBy: provider.rawValue)
        }
    }

    func addManualEntry(name: String, mealType: MealType, calories: Double, protein: Double, carbs: Double, fat: Double) {
        let entry = FoodEntry(
            name: name,
            mealType: mealType,
            source: .manual,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat
        )
        container.nutritionRepository.addEntry(entry)
        refresh()
    }

    func deleteEntry(_ entry: FoodEntry) {
        container.nutritionRepository.deleteEntry(entry)
        refresh()
    }

    private func currentProvider() -> AIProviderKind {
        AIProviderKind(rawValue: container.currentUserSettings().preferredAIProvider) ?? .openAI
    }

    private func runAnalysis(_ operation: @escaping () async throws -> FoodEntry) async {
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }
        do {
            _ = try await operation()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
