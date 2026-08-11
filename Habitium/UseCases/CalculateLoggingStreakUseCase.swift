//
//  CalculateLoggingStreakUseCase.swift
//  Habitium
//
//  Consecutive-day meal-logging streak, shown on Home/FoodTrackerView.
//  Common motivational hook in the best-rated nutrition apps (Lose It!,
//  Fooducate) — counts backward from today (or yesterday, if today hasn't
//  been logged yet) while consecutive days have at least one entry.
//

import Foundation

@MainActor
struct CalculateLoggingStreakUseCase {
    let repository: NutritionRepository

    func execute(referenceDate: Date = .now) -> Int {
        let loggedDates = repository.loggedDates()
        guard !loggedDates.isEmpty else { return 0 }

        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: referenceDate)

        // If today has nothing logged yet, the streak still "counts" from
        // yesterday backward so logging today doesn't reset it to 0 mid-day.
        if !loggedDates.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var streak = 0
        while loggedDates.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
