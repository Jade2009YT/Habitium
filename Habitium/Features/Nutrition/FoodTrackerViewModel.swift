//
//  FoodTrackerViewModel.swift
//  Habitium
//
//  Drives FoodTrackerView: today's logged meals, daily progress, and the
//  async AI-analysis flow (photo or text) via AnalyzeMealUseCase.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class FoodTrackerViewModel {

    private(set) var todayEntries: [FoodEntry] = []
    private(set) var progress: NutritionDailyProgress = .init(
        consumedCalories: 0, goalCalories: 2000, consumedMacros: .zero, goalMacros: .zero
    )
    /// Consecutive days with at least one logged meal — shown as a small
    /// streak badge, borrowed from Lose It!/Fooducate.
    private(set) var loggingStreak: Int = 0
    /// Most recent distinct meals, for one-tap "repetir comida" (à la Lose
    /// It!'s favorites/recents).
    private(set) var recentEntries: [FoodEntry] = []
    /// Last 30 weight measurements, newest first — feeds the trend mini
    /// chart (PlateLens/Lose It!-style).
    private(set) var weightEntries: [WeightEntry] = []
    /// Suggested calorie-goal adjustment based on real weight trend vs.
    /// logged intake — nil unless the user opted in via Settings and there
    /// is enough history to compute one.
    private(set) var adaptiveSuggestion: AdaptiveCalorieGoalSuggestion?

    var isAnalyzing = false
    var errorMessage: String?

    private let container: AppDependencyContainer
    private let barcodeService: BarcodeLookupService

    init(container: AppDependencyContainer, barcodeService: BarcodeLookupService = OpenFoodFactsService()) {
        self.container = container
        self.barcodeService = barcodeService
        refresh()
    }

    func refresh() {
        todayEntries = container.nutritionRepository.entries(on: .now)
        progress = container.makeCalculateRemainingCaloriesUseCase().execute()
        loggingStreak = container.makeCalculateLoggingStreakUseCase().execute()
        recentEntries = container.nutritionRepository.recentUniqueEntries(limit: 6)
        weightEntries = container.nutritionRepository.weightEntries(limit: 30)
        adaptiveSuggestion = container.makeCalculateAdaptiveCalorieGoalUseCase().execute()
    }

    func applyAdaptiveSuggestion() {
        guard let suggestion = adaptiveSuggestion else { return }
        let goal = container.nutritionRepository.currentGoal()
        container.nutritionRepository.updateGoal(
            dailyCalories: suggestion.suggestedCalories,
            proteinGrams: goal.proteinGoalGrams,
            carbsGrams: goal.carbsGoalGrams,
            fatGrams: goal.fatGoalGrams
        )
        refresh()
    }

    /// Re-logs a past entry as a new one today, same macros and meal type —
    /// the one-tap "repetir comida" flow.
    func repeatEntry(_ entry: FoodEntry) {
        let copy = FoodEntry(
            name: entry.name,
            mealType: MealType(rawValue: entry.mealType) ?? .snack,
            source: .manual,
            calories: entry.calories,
            proteinGrams: entry.proteinGrams,
            carbsGrams: entry.carbsGrams,
            fatGrams: entry.fatGrams,
            notes: "Repetido de \(entry.date.formatted(date: .abbreviated, time: .omitted))"
        )
        container.nutritionRepository.addEntry(copy)
        refresh()
    }

    /// Decrypts and decodes a meal's stored photo — triggers Face ID/Touch
    /// ID (see SecureEnclaveCrypto). Returns nil if there's no photo, or
    /// decryption fails/is cancelled.
    func decryptedImage(for entry: FoodEntry) async -> UIImage? {
        guard let data = await container.nutritionRepository.decryptedPhoto(for: entry) else { return nil }
        return UIImage(data: data)
    }

    func logWeight(kg: Double) {
        container.nutritionRepository.addWeightEntry(WeightEntry(weightKg: kg))
        refresh()
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

    /// Looks up a scanned barcode on Open Food Facts (values are per 100 g)
    /// and scales them by the portion the user actually ate.
    func logFromBarcode(_ barcode: String, mealType: MealType, portionGrams: Double) async {
        await runAnalysis {
            let result = try await self.barcodeService.lookupProduct(barcode: barcode)
            let factor = portionGrams / 100.0
            let entry = FoodEntry(
                name: result.mealName,
                mealType: mealType,
                source: .manual,
                calories: result.calories * factor,
                proteinGrams: result.macros.proteinGrams * factor,
                carbsGrams: result.macros.carbsGrams * factor,
                fatGrams: result.macros.fatGrams * factor,
                notes: "Código de barras · porción \(Int(portionGrams)) g",
                analyzedBy: "openfoodfacts"
            )
            self.container.nutritionRepository.addEntry(entry)
            return entry
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
