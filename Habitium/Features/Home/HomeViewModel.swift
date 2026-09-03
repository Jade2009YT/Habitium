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
    private(set) var pendingMedicationDoses: [MedicationDose] = []
    private(set) var habitStatuses: [HabitStatus] = []

    // Progresión — alimenta las tarjetas de nivel/racha y retos de Inicio.
    private(set) var totalXP: Int = 0
    private(set) var loginStreak: Int = 0
    private(set) var dailyChallenges: [DailyChallenge] = []

    var completedChallenges: Int { dailyChallenges.filter(\.isComplete).count }
    var allChallengesDone: Bool {
        !dailyChallenges.isEmpty && completedChallenges == dailyChallenges.count
    }

    var level: Int { ProgressionEngine.level(forTotalXP: totalXP) }
    var levelTitle: String { ProgressionEngine.title(forLevel: level) }
    var levelProgress: Double { ProgressionEngine.progressWithinLevel(totalXP: totalXP) }
    var xpToNextLevel: Int { ProgressionEngine.xpRemainingToNextLevel(totalXP: totalXP) }

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
        pendingMedicationDoses = container.medicationRepository.todaysDoses().filter { $0.isPending }
        habitStatuses = container.habitRepository.todaysStatuses()

        let profile = container.progressionRepository.profile()
        totalXP = profile.totalXP
        loginStreak = profile.loginStreak

        dailyChallenges = container.dailyChallengeService.todaysChallenges()
        // Se comprueba en cada refresco porque los retos se completan
        // desde cualquier pantalla: marcar el tercer hábito en Hábitos
        // debe cobrar la bonificación al volver a Inicio, sin que haya
        // que hacer nada especial allí.
        container.dailyChallengeService.awardBonusIfComplete()
    }

    func toggleFocusTask(_ task: PlannerTask) {
        container.plannerRepository.toggleComplete(task)
        refresh()
    }
}
