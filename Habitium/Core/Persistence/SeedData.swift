//
//  SeedData.swift
//  Habitium
//
//  Ensures the singleton-ish settings rows (NutritionGoal, BudgetSettings,
//  UserSettings) always exist, and optionally seeds sample data for SwiftUI
//  previews.
//

import Foundation
import SwiftData

@MainActor
enum SeedData {

    static func seedIfNeeded(context: ModelContext, forcePreviewData: Bool = false) {
        seedSingletonsIfNeeded(context: context)

        if forcePreviewData {
            seedPreviewData(context: context)
        }

        try? context.save()
    }

    private static func seedSingletonsIfNeeded(context: ModelContext) {
        if (try? context.fetch(FetchDescriptor<NutritionGoal>()))?.isEmpty ?? true {
            context.insert(NutritionGoal())
        }
        if (try? context.fetch(FetchDescriptor<BudgetSettings>()))?.isEmpty ?? true {
            context.insert(BudgetSettings())
        }
        if (try? context.fetch(FetchDescriptor<UserSettings>()))?.isEmpty ?? true {
            context.insert(UserSettings())
        }
    }

    private static func seedPreviewData(context: ModelContext) {
        let calendar = Calendar.current
        let today = Date.now

        context.insert(FoodEntry(name: "Avena con frutas", date: today, mealType: .breakfast, source: .manual, calories: 420, proteinGrams: 18, carbsGrams: 65, fatGrams: 9))
        context.insert(FoodEntry(name: "Pechuga de pollo con arroz", date: today, mealType: .lunch, source: .photo, calories: 650, proteinGrams: 48, carbsGrams: 70, fatGrams: 14))

        context.insert(PlannerEvent(title: "Gimnasio", startDate: calendar.date(byAdding: .hour, value: 2, to: today) ?? today))
        context.insert(PlannerTask(title: "Comprar despensa", dueDate: calendar.date(byAdding: .day, value: 1, to: today)))

        context.insert(Transaction(amount: 45.0, type: .expense, category: .food, note: "Supermercado"))
        context.insert(Transaction(amount: 1200.0, type: .income, category: .salary, note: "Salario"))
    }
}
