//
//  FinanceViewModel.swift
//  Habitium
//
//  Drives FinanceView: this month's overview (available to spend, budget
//  progress, savings) plus the transaction list and quick-add flow.
//

import Foundation
import Observation

@MainActor
@Observable
final class FinanceViewModel {

    private(set) var overview: FinanceOverview = .init(
        availableToSpend: 0, monthlyBudget: 0, monthlySpent: 0, totalSavings: 0, currencyCode: "USD"
    )
    private(set) var transactions: [Transaction] = []

    private let container: AppDependencyContainer
    private var repository: FinanceRepository { container.financeRepository }

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        overview = container.makeCalculateAvailableBudgetUseCase().execute()
        transactions = repository.transactions(in: .now)
    }

    func addTransaction(amount: Double, type: TransactionType, category: TransactionCategory, note: String?) {
        repository.addTransaction(Transaction(amount: amount, type: type, category: category, note: note))
        refresh()
    }

    func deleteTransaction(_ transaction: Transaction) {
        repository.deleteTransaction(transaction)
        refresh()
    }

    func updateBudget(monthlyBudget: Double, totalSavings: Double) {
        repository.updateBudget(monthlyBudget: monthlyBudget, totalSavings: totalSavings, currencyCode: overview.currencyCode)
        refresh()
    }
}
