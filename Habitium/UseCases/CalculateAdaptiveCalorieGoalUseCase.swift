//
//  CalculateAdaptiveCalorieGoalUseCase.swift
//  Habitium
//
//  PlateLens' signature idea: instead of a calorie goal you set once and
//  forget, estimate your *real* maintenance calories from what you've
//  actually logged vs. how your weight actually moved, then suggest a new
//  goal to hit your chosen weekly rate of change. Entirely on-device, no
//  AI call — just the standard ~7700 kcal ≈ 1 kg energy-balance estimate.
//
//  Opt-in: only produces a suggestion when the user has set
//  NutritionGoal.weeklyRateKg (in Settings) and has enough logged history.
//

import Foundation

struct AdaptiveCalorieGoalSuggestion: Equatable {
    var suggestedCalories: Double
    var currentCalories: Double
    var estimatedMaintenanceCalories: Double
    var observedWeeklyRateKg: Double
    var windowDays: Int

    var difference: Double { suggestedCalories - currentCalories }
}

@MainActor
struct CalculateAdaptiveCalorieGoalUseCase {
    let repository: NutritionRepository

    private let kcalPerKg = 7700.0
    private let minWindowDays = 10
    private let maxWindowDays = 30
    private let minActionableDifference = 50.0

    func execute() -> AdaptiveCalorieGoalSuggestion? {
        let goal = repository.currentGoal()
        guard let weeklyRateGoal = goal.weeklyRateKg else { return nil }

        // Newest-first; oldest entry still inside the analysis window.
        let weights = repository.weightEntries(limit: 60)
        guard let newest = weights.first else { return nil }
        let windowStart = Calendar.current.date(byAdding: .day, value: -maxWindowDays, to: .now) ?? .distantPast
        guard let oldest = weights.last(where: { $0.date >= windowStart }), oldest.id != newest.id else { return nil }

        let days = max(1, Calendar.current.dateComponents([.day], from: oldest.date, to: newest.date).day ?? 0)
        guard days >= minWindowDays else { return nil }

        let observedDeltaKg = newest.weightKg - oldest.weightKg
        let dailyEntries = repository.entriesInLastDays(days)
        guard !dailyEntries.isEmpty else { return nil }

        let byDay = Dictionary(grouping: dailyEntries) { Calendar.current.startOfDay(for: $0.date) }
        let dailyTotals = byDay.values.map { entries in entries.reduce(0) { $0 + $1.calories } }
        guard !dailyTotals.isEmpty else { return nil }
        let avgLoggedCalories = dailyTotals.reduce(0, +) / Double(dailyTotals.count)

        let estimatedMaintenance = avgLoggedCalories - (observedDeltaKg * kcalPerKg / Double(days))
        let desiredDailyDelta = weeklyRateGoal * kcalPerKg / 7
        let suggested = max(1200, (estimatedMaintenance + desiredDailyDelta).rounded())

        let suggestion = AdaptiveCalorieGoalSuggestion(
            suggestedCalories: suggested,
            currentCalories: goal.dailyCalorieGoal,
            estimatedMaintenanceCalories: estimatedMaintenance.rounded(),
            observedWeeklyRateKg: (observedDeltaKg / Double(days)) * 7,
            windowDays: days
        )
        guard abs(suggestion.difference) >= minActionableDifference else { return nil }
        return suggestion
    }
}
