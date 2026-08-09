//
//  SharedDataStore.swift
//  Habitium
//
//  Bridges the main app and the widget extension. Widgets run in a
//  separate process and, for reliability, don't query SwiftData directly —
//  instead the app writes small Codable snapshots to the shared App Group
//  UserDefaults suite every time relevant data changes, and calls
//  WidgetCenter.reloadAllTimelines(). Widget timeline providers just decode
//  the latest snapshot. This file is compiled into BOTH targets (add it to
//  both target memberships in Xcode, or list it under both `sources` in
//  project.yml) so the struct definitions stay in sync.
//

import Foundation

struct NutritionWidgetSnapshot: Codable {
    var consumedCalories: Double
    var goalCalories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var lastMealName: String?
    var updatedAt: Date

    static let placeholder = NutritionWidgetSnapshot(
        consumedCalories: 1200,
        goalCalories: 2000,
        proteinGrams: 80,
        carbsGrams: 140,
        fatGrams: 40,
        lastMealName: "Almuerzo",
        updatedAt: .now
    )
}

struct FinanceWidgetSnapshot: Codable {
    var availableToSpend: Double
    var monthlyBudget: Double
    var totalSavings: Double
    var currencyCode: String
    var updatedAt: Date

    static let placeholder = FinanceWidgetSnapshot(
        availableToSpend: 350,
        monthlyBudget: 1000,
        totalSavings: 2400,
        currencyCode: "USD",
        updatedAt: .now
    )
}

struct CalendarWidgetSnapshot: Codable {
    struct UpcomingItem: Codable, Identifiable {
        var id: UUID
        var title: String
        var date: Date
        var isTask: Bool
    }

    var items: [UpcomingItem]
    var updatedAt: Date

    static let placeholder = CalendarWidgetSnapshot(
        items: [
            .init(id: UUID(), title: "Gimnasio", date: .now.addingTimeInterval(3600), isTask: false),
            .init(id: UUID(), title: "Comprar despensa", date: .now.addingTimeInterval(7200), isTask: true)
        ],
        updatedAt: .now
    )
}

/// Thin wrapper around the shared UserDefaults suite. Safe to call from
/// either the app or the widget extension.
enum SharedDataStore {

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    private enum Key {
        static let nutrition = "widget.nutrition.snapshot"
        static let finance = "widget.finance.snapshot"
        static let calendar = "widget.calendar.snapshot"
    }

    // MARK: - Nutrition

    static func writeNutritionSnapshot(_ snapshot: NutritionWidgetSnapshot) {
        write(snapshot, forKey: Key.nutrition)
    }

    static func readNutritionSnapshot() -> NutritionWidgetSnapshot {
        read(NutritionWidgetSnapshot.self, forKey: Key.nutrition) ?? .placeholder
    }

    // MARK: - Finance

    static func writeFinanceSnapshot(_ snapshot: FinanceWidgetSnapshot) {
        write(snapshot, forKey: Key.finance)
    }

    static func readFinanceSnapshot() -> FinanceWidgetSnapshot {
        read(FinanceWidgetSnapshot.self, forKey: Key.finance) ?? .placeholder
    }

    // MARK: - Calendar

    static func writeCalendarSnapshot(_ snapshot: CalendarWidgetSnapshot) {
        write(snapshot, forKey: Key.calendar)
    }

    static func readCalendarSnapshot() -> CalendarWidgetSnapshot {
        read(CalendarWidgetSnapshot.self, forKey: Key.calendar) ?? .placeholder
    }

    // MARK: - Generic helpers

    private static func write<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
