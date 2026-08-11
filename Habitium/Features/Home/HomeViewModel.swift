//
//  HomeViewModel.swift
//  Habitium
//
//  Aggregates the three use cases needed for the unified dashboard:
//  remaining calories, next upcoming items, and available budget.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {

    private(set) var nutritionProgress: NutritionDailyProgress = .init(
        consumedCalories: 0, goalCalories: 2000, consumedMacros: .zero, goalMacros: .zero
    )
    private(set) var upcomingItems: [UpcomingPlannerItem] = []
    private(set) var financeOverview: FinanceOverview = .init(
        availableToSpend: 0, monthlyBudget: 0, monthlySpent: 0, totalSavings: 0, currencyCode: "USD"
    )
    /// Today's "foco del día" (Sunsama-style) — at most 3, set from the
    /// Planner tab.
    private(set) var focusTasks: [PlannerTask] = []

    private let container: AppDependencyContainer

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        nutritionProgress = container.makeCalculateRemainingCaloriesUseCase().execute()
        upcomingItems = container.makeFetchUpcomingEventsUseCase().execute(limit: 3)
        financeOverview = container.makeCalculateAvailableBudgetUseCase().execute()
        focusTasks = container.plannerRepository.focusTasks()
    }

    func toggleFocusTask(_ task: PlannerTask) {
        container.plannerRepository.toggleComplete(task)
        refresh()
    }
}
