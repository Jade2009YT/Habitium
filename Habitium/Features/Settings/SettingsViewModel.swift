//
//  SettingsViewModel.swift
//  Habitium
//
//  Drives SettingsView: nutrition goals, AI provider, notification
//  preferences, currency, and the (currently unused) subscription status.
//

import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {

    // Nutrition goals
    var dailyCalorieGoal: Double
    var proteinGoalGrams: Double
    var carbsGoalGrams: Double
    var fatGoalGrams: Double

    // Preferences
    var preferredAIProvider: AIProviderKind
    var mealReminderNotificationsEnabled: Bool
    var eventNotificationsEnabled: Bool
    var mealReminderHour: Int
    var mealReminderMinute: Int

    // Finance
    var currencyCode: String

    let container: AppDependencyContainer

    init(container: AppDependencyContainer) {
        self.container = container

        let goal = container.nutritionRepository.currentGoal()
        dailyCalorieGoal = goal.dailyCalorieGoal
        proteinGoalGrams = goal.proteinGoalGrams
        carbsGoalGrams = goal.carbsGoalGrams
        fatGoalGrams = goal.fatGoalGrams

        let settings = container.currentUserSettings()
        preferredAIProvider = AIProviderKind(rawValue: settings.preferredAIProvider) ?? .openAI
        mealReminderNotificationsEnabled = settings.mealReminderNotificationsEnabled
        eventNotificationsEnabled = settings.eventNotificationsEnabled
        mealReminderHour = 19
        mealReminderMinute = 0

        currencyCode = container.financeRepository.currentBudget().currencyCode
    }

    func saveGoals() {
        container.nutritionRepository.updateGoal(
            dailyCalories: dailyCalorieGoal,
            proteinGrams: proteinGoalGrams,
            carbsGrams: carbsGoalGrams,
            fatGrams: fatGoalGrams
        )
    }

    func savePreferences() {
        container.updateUserSettings(
            aiProvider: preferredAIProvider,
            mealReminders: mealReminderNotificationsEnabled,
            eventNotifications: eventNotificationsEnabled
        )

        if mealReminderNotificationsEnabled {
            NotificationScheduler.shared.scheduleDailyMealReminder(hour: mealReminderHour, minute: mealReminderMinute)
        } else {
            NotificationScheduler.shared.cancelDailyMealReminder()
        }
    }

    func saveCurrency() {
        let budget = container.financeRepository.currentBudget()
        container.financeRepository.updateBudget(monthlyBudget: budget.monthlyBudget, totalSavings: budget.totalSavings, currencyCode: currencyCode)
    }
}
