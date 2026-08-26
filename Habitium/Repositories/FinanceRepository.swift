//
//  FinanceRepository.swift
//  Habitium
//
//  Data-layer abstraction over Transaction/BudgetSettings persistence and
//  the derived numbers (monthly spent, available to spend) used across
//  FinanceView, HomeView and the finance widget.
//

import Foundation
import SwiftData

@MainActor
protocol FinanceRepository {
    func transactions(in monthOf: Date) -> [Transaction]
    func addTransaction(_ transaction: Transaction)
    func deleteTransaction(_ transaction: Transaction)

    func currentBudget() -> BudgetSettings
    func updateBudget(monthlyBudget: Double, totalSavings: Double, currencyCode: String)
    func updateSavingsGoal(amount: Double?, date: Date?)

    /// Sum of expenses this month (positive number).
    func monthlySpent() -> Double
    /// monthlyBudget - monthlySpent (never below 0 for display purposes,
    /// callers can still detect an overspend from monthlySpent()).
    func availableToSpend() -> Double

    /// Spent-per-category this month (expenses only) — feeds the category
    /// breakdown donut chart and per-category budget bars.
    func spentByCategory(in monthOf: Date) -> [TransactionCategory: Double]

    // Per-category envelope budgets (Goodbudget/Monarch-style)
    func categoryBudgets() -> [CategoryBudget]
    func setCategoryBudget(_ category: TransactionCategory, monthlyLimit: Double)
    func removeCategoryBudget(_ category: TransactionCategory)

    // Recurring transactions (Monarch/EveryDollar-style fixed monthly bills)
    func recurringTransactions() -> [RecurringTransaction]
    func addRecurringTransaction(_ transaction: RecurringTransaction)
    func deleteRecurringTransaction(_ transaction: RecurringTransaction)
    func setRecurringTransactionActive(_ transaction: RecurringTransaction, isActive: Bool)
    /// Logs a real Transaction for every active recurring item whose day
    /// has arrived and hasn't been applied yet this month. Safe to call on
    /// every launch/foreground — returns how many were applied.
    @discardableResult
    func applyDueRecurringTransactions() -> Int
}

@MainActor
final class SwiftDataFinanceRepository: FinanceRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func transactions(in monthOf: Date) -> [Transaction] {
        let range = Calendar.current.monthRange(containing: monthOf)
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.date >= range.lowerBound && transaction.date < range.upperBound
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func addTransaction(_ transaction: Transaction) {
        context.insert(transaction)
        save()
        syncWidgetSnapshot()
    }

    func deleteTransaction(_ transaction: Transaction) {
        context.insert(PendingCloudDeletion(table: "transactions", recordID: transaction.id))
        context.delete(transaction)
        save()
        syncWidgetSnapshot()
    }

    func currentBudget() -> BudgetSettings {
        if let existing = try? context.fetch(FetchDescriptor<BudgetSettings>()).first {
            return existing
        }
        let budget = BudgetSettings()
        context.insert(budget)
        save()
        return budget
    }

    func updateBudget(monthlyBudget: Double, totalSavings: Double, currencyCode: String) {
        let budget = currentBudget()
        budget.monthlyBudget = monthlyBudget
        budget.totalSavings = totalSavings
        budget.currencyCode = currencyCode
        budget.updatedAt = .now
        save()
        syncWidgetSnapshot()
    }

    func updateSavingsGoal(amount: Double?, date: Date?) {
        let budget = currentBudget()
        budget.savingsGoalAmount = amount
        budget.savingsGoalDate = date
        budget.updatedAt = .now
        save()
    }

    func monthlySpent() -> Double {
        transactions(in: .now)
            .filter { $0.type == TransactionType.expense.rawValue }
            .reduce(0) { $0 + $1.amount }
    }

    func availableToSpend() -> Double {
        max(0, currentBudget().monthlyBudget - monthlySpent())
    }

    func spentByCategory(in monthOf: Date) -> [TransactionCategory: Double] {
        var totals: [TransactionCategory: Double] = [:]
        for transaction in transactions(in: monthOf) where transaction.type == TransactionType.expense.rawValue {
            guard let category = TransactionCategory(rawValue: transaction.category) else { continue }
            totals[category, default: 0] += transaction.amount
        }
        return totals
    }

    func categoryBudgets() -> [CategoryBudget] {
        (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []
    }

    func setCategoryBudget(_ category: TransactionCategory, monthlyLimit: Double) {
        if let existing = categoryBudgets().first(where: { $0.category == category.rawValue }) {
            existing.monthlyLimit = monthlyLimit
            existing.updatedAt = .now
        } else {
            context.insert(CategoryBudget(category: category, monthlyLimit: monthlyLimit))
        }
        save()
    }

    func removeCategoryBudget(_ category: TransactionCategory) {
        if let existing = categoryBudgets().first(where: { $0.category == category.rawValue }) {
            context.insert(PendingCloudDeletion(table: "category_budgets", recordID: existing.id))
            context.delete(existing)
            save()
        }
    }

    func recurringTransactions() -> [RecurringTransaction] {
        (try? context.fetch(FetchDescriptor<RecurringTransaction>(sortBy: [SortDescriptor(\.dayOfMonth)]))) ?? []
    }

    func addRecurringTransaction(_ transaction: RecurringTransaction) {
        context.insert(transaction)
        save()
    }

    func deleteRecurringTransaction(_ transaction: RecurringTransaction) {
        context.insert(PendingCloudDeletion(table: "recurring_transactions", recordID: transaction.id))
        context.delete(transaction)
        save()
    }

    func setRecurringTransactionActive(_ transaction: RecurringTransaction, isActive: Bool) {
        transaction.isActive = isActive
        transaction.updatedAt = .now
        save()
    }

    @discardableResult
    func applyDueRecurringTransactions() -> Int {
        let calendar = Calendar.current
        let today = Date.now
        let currentMonthStart = calendar.monthRange(containing: today).lowerBound
        let todayDay = calendar.component(.day, from: today)

        var appliedCount = 0
        for recurring in recurringTransactions() where recurring.isActive {
            let alreadyAppliedThisMonth = recurring.lastAppliedMonth.map { calendar.isDate($0, equalTo: currentMonthStart, toGranularity: .month) } ?? false
            guard !alreadyAppliedThisMonth, todayDay >= recurring.dayOfMonth,
                  let type = TransactionType(rawValue: recurring.type),
                  let category = TransactionCategory(rawValue: recurring.category) else { continue }

            let transaction = Transaction(amount: recurring.amount, type: type, category: category, note: recurring.name)
            context.insert(transaction)
            recurring.lastAppliedMonth = currentMonthStart
            recurring.updatedAt = .now
            appliedCount += 1
        }
        if appliedCount > 0 {
            save()
            syncWidgetSnapshot()
        }
        return appliedCount
    }

    private func save() {
        try? context.save()
    }

    private func syncWidgetSnapshot() {
        let budget = currentBudget()
        let snapshot = FinanceWidgetSnapshot(
            availableToSpend: availableToSpend(),
            monthlyBudget: budget.monthlyBudget,
            totalSavings: budget.totalSavings,
            currencyCode: budget.currencyCode,
            updatedAt: .now
        )
        SharedDataStore.writeFinanceSnapshot(snapshot)
        WidgetRefresher.reloadFinanceWidget()
        WatchConnectivityBridge.shared.sendCurrentSnapshots()
    }
}

extension Calendar {
    /// [startOfMonth, startOfNextMonth) containing `date`.
    func monthRange(containing date: Date) -> Range<Date> {
        let start = self.date(from: dateComponents([.year, .month], from: date)) ?? date
        let end = self.date(byAdding: .month, value: 1, to: start) ?? start
        return start..<end
    }
}
