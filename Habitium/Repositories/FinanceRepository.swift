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

    /// Sum of expenses this month (positive number).
    func monthlySpent() -> Double
    /// monthlyBudget - monthlySpent (never below 0 for display purposes,
    /// callers can still detect an overspend from monthlySpent()).
    func availableToSpend() -> Double
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

    func monthlySpent() -> Double {
        transactions(in: .now)
            .filter { $0.type == TransactionType.expense.rawValue }
            .reduce(0) { $0 + $1.amount }
    }

    func availableToSpend() -> Double {
        max(0, currentBudget().monthlyBudget - monthlySpent())
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
