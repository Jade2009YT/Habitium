//
//  AppDependencyContainer.swift
//  Habitium
//
//  Composition root: builds the repositories and use cases once and hands
//  them out to ViewModels. Injected into the SwiftUI environment from
//  HabitiumApp so features never construct their own dependencies.
//

import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppDependencyContainer {

    let nutritionRepository: NutritionRepository
    let plannerRepository: PlannerRepository
    let financeRepository: FinanceRepository
    let medicationRepository: MedicationRepository
    let habitRepository: HabitRepository
    let workoutRepository: WorkoutRepository
    /// StoreKit scaffold for a possible future "Habitium Pro" subscription.
    /// Nothing in the app currently checks `isProActive` — everything is
    /// unlocked for personal use.
    let subscriptionManager = SubscriptionManager()

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.nutritionRepository = SwiftDataNutritionRepository(context: modelContext)
        self.plannerRepository = SwiftDataPlannerRepository(context: modelContext)
        self.financeRepository = SwiftDataFinanceRepository(context: modelContext)
        self.medicationRepository = SwiftDataMedicationRepository(context: modelContext)
        self.habitRepository = SwiftDataHabitRepository(context: modelContext)
        self.workoutRepository = SwiftDataWorkoutRepository(context: modelContext, habitRepository: self.habitRepository)
    }

    // MARK: - Use case factories
    // Use cases are cheap value/struct types, built on demand rather than
    // stored, so each ViewModel gets its own instance without shared state.

    func makeAnalyzeMealUseCase(provider: AIProviderKind) -> AnalyzeMealUseCase {
        AnalyzeMealUseCase(analyzer: FoodAnalysisServiceFactory.make(for: provider), repository: nutritionRepository)
    }

    func makeCalculateRemainingCaloriesUseCase() -> CalculateRemainingCaloriesUseCase {
        CalculateRemainingCaloriesUseCase(repository: nutritionRepository)
    }

    func makeCalculateAvailableBudgetUseCase() -> CalculateAvailableBudgetUseCase {
        CalculateAvailableBudgetUseCase(repository: financeRepository)
    }

    func makeFetchUpcomingEventsUseCase() -> FetchUpcomingEventsUseCase {
        FetchUpcomingEventsUseCase(repository: plannerRepository)
    }

    func makeCalculateLoggingStreakUseCase() -> CalculateLoggingStreakUseCase {
        CalculateLoggingStreakUseCase(repository: nutritionRepository)
    }

    func makeCalculateAdaptiveCalorieGoalUseCase() -> CalculateAdaptiveCalorieGoalUseCase {
        CalculateAdaptiveCalorieGoalUseCase(repository: nutritionRepository)
    }

    func currentUserSettings() -> UserSettings {
        if let existing = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first {
            return existing
        }
        let settings = UserSettings()
        modelContext.insert(settings)
        try? modelContext.save()
        return settings
    }

    func updateUserSettings(aiProvider: AIProviderKind, mealReminders: Bool, eventNotifications: Bool) {
        let settings = currentUserSettings()
        settings.preferredAIProvider = aiProvider.rawValue
        settings.mealReminderNotificationsEnabled = mealReminders
        settings.eventNotificationsEnabled = eventNotifications
        try? modelContext.save()
    }

    /// Persists the display name/email Sign in with Apple hands over on
    /// first authorization. Only overwrites a field when a new non-nil
    /// value is provided, since Apple won't send them again later.
    func applyAppleIdentity(displayName: String?, email: String?) {
        let settings = currentUserSettings()
        if let displayName { settings.displayName = displayName }
        if let email { settings.email = email }
        try? modelContext.save()
    }
}
