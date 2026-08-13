//
//  NutritionRepository.swift
//  Habitium
//
//  Data-layer abstraction over FoodEntry/NutritionGoal persistence. The
//  protocol lets ViewModels and UseCases depend on an interface instead of
//  SwiftData directly (Clean Architecture), which also makes them testable
//  with a fake in unit tests.
//

import Foundation
import SwiftData

@MainActor
protocol NutritionRepository {
    func entries(on date: Date) -> [FoodEntry]
    func addEntry(_ entry: FoodEntry)
    func deleteEntry(_ entry: FoodEntry)

    /// Decrypts a meal photo for viewing (see SecureEnclaveCrypto) —
    /// prompts Face ID/Touch ID. Returns nil if the entry has no photo or
    /// decryption fails/is cancelled.
    func decryptedPhoto(for entry: FoodEntry) async -> Data?

    /// Most recent entries, deduplicated by name (latest occurrence wins) —
    /// feeds the "repetir comida" quick-add list (à la Lose It!'s
    /// favorites/recents).
    func recentUniqueEntries(limit: Int) -> [FoodEntry]

    /// Start-of-day dates that have at least one logged entry — used to
    /// compute the logging streak.
    func loggedDates() -> Set<Date>

    /// All entries logged in the last `days` days (including today) —
    /// used to compute an average daily intake for the adaptive goal
    /// suggestion.
    func entriesInLastDays(_ days: Int) -> [FoodEntry]

    func currentGoal() -> NutritionGoal
    func updateGoal(dailyCalories: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double)
    /// Opt-in settings for the adaptive calorie goal suggestion. Pass nil
    /// for weeklyRateKg to turn the suggestion off entirely.
    func updateAdaptiveGoalSettings(targetWeightKg: Double?, weeklyRateKg: Double?)

    // Weight trend (PlateLens/Lose It!-style)
    func addWeightEntry(_ entry: WeightEntry)
    func weightEntries(limit: Int) -> [WeightEntry]
}

@MainActor
final class SwiftDataNutritionRepository: NutritionRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func entries(on date: Date) -> [FoodEntry] {
        let range = Calendar.current.dayRange(containing: date)
        let predicate = #Predicate<FoodEntry> { entry in
            entry.date >= range.lowerBound && entry.date < range.upperBound
        }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func addEntry(_ entry: FoodEntry) {
        // Meal photos are the one blob worth the extra protection — encrypt
        // in place before it ever touches disk. This is fast and never
        // prompts Face ID (see SecureEnclaveCrypto).
        if let rawImage = entry.imageData {
            entry.imageData = (try? SecureEnclaveCrypto.shared.encrypt(rawImage)) ?? rawImage
        }
        context.insert(entry)
        save()
        syncWidgetSnapshot()
    }

    func deleteEntry(_ entry: FoodEntry) {
        context.delete(entry)
        save()
        syncWidgetSnapshot()
    }

    func decryptedPhoto(for entry: FoodEntry) async -> Data? {
        guard let encrypted = entry.imageData else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? SecureEnclaveCrypto.shared.decrypt(encrypted)
        }.value
    }

    func recentUniqueEntries(limit: Int) -> [FoodEntry] {
        let descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        var seenNames = Set<String>()
        var result: [FoodEntry] = []
        for entry in all {
            let key = entry.name.lowercased()
            guard !seenNames.contains(key) else { continue }
            seenNames.insert(key)
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    func loggedDates() -> Set<Date> {
        let descriptor = FetchDescriptor<FoodEntry>()
        let all = (try? context.fetch(descriptor)) ?? []
        return Set(all.map { Calendar.current.startOfDay(for: $0.date) })
    }

    func entriesInLastDays(_ days: Int) -> [FoodEntry] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) ?? .distantPast
        let predicate = #Predicate<FoodEntry> { entry in entry.date >= start }
        let descriptor = FetchDescriptor<FoodEntry>(predicate: predicate)
        return (try? context.fetch(descriptor)) ?? []
    }

    func addWeightEntry(_ entry: WeightEntry) {
        context.insert(entry)
        save()
    }

    func weightEntries(limit: Int) -> [WeightEntry] {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func currentGoal() -> NutritionGoal {
        if let existing = try? context.fetch(FetchDescriptor<NutritionGoal>()).first {
            return existing
        }
        let goal = NutritionGoal()
        context.insert(goal)
        save()
        return goal
    }

    func updateGoal(dailyCalories: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double) {
        let goal = currentGoal()
        goal.dailyCalorieGoal = dailyCalories
        goal.proteinGoalGrams = proteinGrams
        goal.carbsGoalGrams = carbsGrams
        goal.fatGoalGrams = fatGrams
        goal.updatedAt = .now
        save()
        syncWidgetSnapshot()
    }

    func updateAdaptiveGoalSettings(targetWeightKg: Double?, weeklyRateKg: Double?) {
        let goal = currentGoal()
        goal.targetWeightKg = targetWeightKg
        goal.weeklyRateKg = weeklyRateKg
        goal.updatedAt = .now
        save()
    }

    private func save() {
        try? context.save()
    }

    /// Publishes today's totals to the shared App Group store so the
    /// nutrition widget stays fresh, then asks WidgetKit to reload.
    private func syncWidgetSnapshot() {
        let todayEntries = entries(on: .now)
        let goal = currentGoal()
        let snapshot = NutritionWidgetSnapshot(
            consumedCalories: todayEntries.reduce(0) { $0 + $1.calories },
            goalCalories: goal.dailyCalorieGoal,
            proteinGrams: todayEntries.reduce(0) { $0 + $1.proteinGrams },
            carbsGrams: todayEntries.reduce(0) { $0 + $1.carbsGrams },
            fatGrams: todayEntries.reduce(0) { $0 + $1.fatGrams },
            lastMealName: todayEntries.last?.name,
            updatedAt: .now
        )
        SharedDataStore.writeNutritionSnapshot(snapshot)
        WidgetRefresher.reloadNutritionWidget()
    }
}

extension Calendar {
    /// [startOfDay, startOfNextDay) — used by all three repositories to
    /// scope "today" queries.
    func dayRange(containing date: Date) -> Range<Date> {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start) ?? start
        return start..<end
    }
}
