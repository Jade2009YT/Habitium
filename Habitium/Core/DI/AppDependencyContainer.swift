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
}
