//
//  CalculateAvailableBudgetUseCase.swift
//  Habitium
//
//  Domain-layer calculation shared by HomeView and FinanceView.
//

import Foundation

struct FinanceOverview: Equatable {
    var availableToSpend: Double
    var monthlyBudget: Double
    var monthlySpent: Double
    var totalSavings: Double
    var currencyCode: String

    var spentProgress: Double { monthlyBudget > 0 ? min(monthlySpent / monthlyBudget, 1.0) : 0 }
    var isOverBudget: Bool { monthlySpent > monthlyBudget }
}

@MainActor
struct CalculateAvailableBudgetUseCase {
    let repository: FinanceRepository

    func execute() -> FinanceOverview {
        let budget = repository.currentBudget()
        let spent = repository.monthlySpent()
        return FinanceOverview(
            availableToSpend: max(0, budget.monthlyBudget - spent),
            monthlyBudget: budget.monthlyBudget,
            monthlySpent: spent,
            totalSavings: budget.totalSavings,
            currencyCode: budget.currencyCode
        )
    }
}
