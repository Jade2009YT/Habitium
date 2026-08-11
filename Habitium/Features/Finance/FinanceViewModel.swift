//
//  FinanceViewModel.swift
//  Habitium
//
//  Drives FinanceView: this month's overview (available to spend, budget
//  progress, savings) plus the transaction list, category breakdown,
//  per-category envelope budgets, and the savings goal.
//

import Foundation
import Observation

struct CategorySpendingRow: Identifiable {
    var category: TransactionCategory
    var spent: Double
    var limit: Double?

    var id: String { category.rawValue }
    var progress: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(spent / limit, 1.0)
    }
    var isOverLimit: Bool {
        guard let limit else { return false }
        return spent > limit
    }
}

@MainActor
@Observable
final class FinanceViewModel {

    private(set) var overview: FinanceOverview = .init(
        availableToSpend: 0, monthlyBudget: 0, monthlySpent: 0, totalSavings: 0, currencyCode: "USD"
    )
    private(set) var transactions: [Transaction] = []
    /// Spending broken down by category this month, sorted highest first —
    /// feeds both the donut chart and the per-category budget bars
    /// (Monarch Money/Goodbudget-style envelope budgeting).
    private(set) var categoryBreakdown: [CategorySpendingRow] = []
    private(set) var savingsGoalAmount: Double?
    private(set) var savingsGoalDate: Date?
    private(set) var recurringTransactions: [RecurringTransaction] = []

    private let container: AppDependencyContainer
    private var repository: FinanceRepository { container.financeRepository }

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        overview = container.makeCalculateAvailableBudgetUseCase().execute()
        transactions = repository.transactions(in: .now)

        let spending = repository.spentByCategory(in: .now)
        let limits = Dictionary(uniqueKeysWithValues: repository.categoryBudgets().compactMap { budget -> (TransactionCategory, Double)? in
            guard let category = TransactionCategory(rawValue: budget.category) else { return nil }
            return (category, budget.monthlyLimit)
        })
        let categories = Set(spending.keys).union(limits.keys)
        categoryBreakdown = categories
            .map { CategorySpendingRow(category: $0, spent: spending[$0] ?? 0, limit: limits[$0]) }
            .sorted { $0.spent > $1.spent }

        let budget = repository.currentBudget()
        savingsGoalAmount = budget.savingsGoalAmount
        savingsGoalDate = budget.savingsGoalDate

        recurringTransactions = repository.recurringTransactions()
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

    func updateSavingsGoal(amount: Double?, date: Date?) {
        repository.updateSavingsGoal(amount: amount, date: date)
        refresh()
    }

    func setCategoryLimit(_ category: TransactionCategory, limit: Double) {
        repository.setCategoryBudget(category, monthlyLimit: limit)
        refresh()
    }

    func removeCategoryLimit(_ category: TransactionCategory) {
        repository.removeCategoryBudget(category)
        refresh()
    }

    func addRecurringTransaction(name: String, amount: Double, type: TransactionType, category: TransactionCategory, dayOfMonth: Int) {
        repository.addRecurringTransaction(RecurringTransaction(name: name, amount: amount, type: type, category: category, dayOfMonth: dayOfMonth))
        refresh()
    }

    func deleteRecurringTransaction(_ transaction: RecurringTransaction) {
        repository.deleteRecurringTransaction(transaction)
        refresh()
    }

    func setRecurringTransactionActive(_ transaction: RecurringTransaction, isActive: Bool) {
        repository.setRecurringTransactionActive(transaction, isActive: isActive)
        refresh()
    }
}
