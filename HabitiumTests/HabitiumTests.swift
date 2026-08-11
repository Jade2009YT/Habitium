//
//  HabitiumTests.swift
//  HabitiumTests
//
//  Unit tests for the domain layer (UseCases), exercised against fake
//  repositories so they don't touch SwiftData at all. This is the payoff
//  of the Clean Architecture split: business logic is testable in
//  isolation from persistence and networking.
//

import XCTest
@testable import Habitium

@MainActor
final class HabitiumTests: XCTestCase {

    func testRemainingCaloriesUseCase() {
        let repository = FakeNutritionRepository()
        repository.entriesToday = [
            FoodEntry(name: "Desayuno", calories: 500, proteinGrams: 20, carbsGrams: 60, fatGrams: 15)
        ]
        repository.goal = NutritionGoal(dailyCalorieGoal: 2000, proteinGoalGrams: 120, carbsGoalGrams: 225, fatGoalGrams: 65)

        let result = CalculateRemainingCaloriesUseCase(repository: repository).execute()

        XCTAssertEqual(result.consumedCalories, 500)
        XCTAssertEqual(result.remainingCalories, 1500)
        XCTAssertFalse(result.isOverGoal)
    }

    func testAvailableBudgetUseCaseClampsAtZeroWhenOverspent() {
        let repository = FakeFinanceRepository()
        repository.budget = BudgetSettings(monthlyBudget: 500, totalSavings: 1000)
        repository.spent = 750

        let result = CalculateAvailableBudgetUseCase(repository: repository).execute()

        XCTAssertEqual(result.availableToSpend, 0)
        XCTAssertTrue(result.isOverBudget)
    }
}

// MARK: - Fakes

@MainActor
private final class FakeNutritionRepository: NutritionRepository {
    var entriesToday: [FoodEntry] = []
    var goal = NutritionGoal()

    func entries(on date: Date) -> [FoodEntry] { entriesToday }
    func addEntry(_ entry: FoodEntry) { entriesToday.append(entry) }
    func deleteEntry(_ entry: FoodEntry) { entriesToday.removeAll { $0.id == entry.id } }
    func currentGoal() -> NutritionGoal { goal }
    func updateGoal(dailyCalories: Double, proteinGrams: Double, carbsGrams: Double, fatGrams: Double) {
        goal.dailyCalorieGoal = dailyCalories
    }
    func updateAdaptiveGoalSettings(targetWeightKg: Double?, weeklyRateKg: Double?) {
        goal.targetWeightKg = targetWeightKg
        goal.weeklyRateKg = weeklyRateKg
    }
    func recentUniqueEntries(limit: Int) -> [FoodEntry] { Array(entriesToday.prefix(limit)) }
    func loggedDates() -> Set<Date> { Set(entriesToday.map { Calendar.current.startOfDay(for: $0.date) }) }
    func entriesInLastDays(_ days: Int) -> [FoodEntry] { entriesToday }

    var storedWeights: [WeightEntry] = []
    func addWeightEntry(_ entry: WeightEntry) { storedWeights.append(entry) }
    func weightEntries(limit: Int) -> [WeightEntry] { Array(storedWeights.prefix(limit)) }
}

@MainActor
private final class FakeFinanceRepository: FinanceRepository {
    var budget = BudgetSettings()
    var spent: Double = 0
    var storedTransactions: [Transaction] = []

    func transactions(in monthOf: Date) -> [Transaction] { storedTransactions }
    func addTransaction(_ transaction: Transaction) { storedTransactions.append(transaction) }
    func deleteTransaction(_ transaction: Transaction) { storedTransactions.removeAll { $0.id == transaction.id } }
    func currentBudget() -> BudgetSettings { budget }
    func updateBudget(monthlyBudget: Double, totalSavings: Double, currencyCode: String) {
        budget.monthlyBudget = monthlyBudget
        budget.totalSavings = totalSavings
    }
    func monthlySpent() -> Double { spent }
    func availableToSpend() -> Double { max(0, budget.monthlyBudget - spent) }
    func updateSavingsGoal(amount: Double?, date: Date?) {
        budget.savingsGoalAmount = amount
        budget.savingsGoalDate = date
    }
    func spentByCategory(in monthOf: Date) -> [TransactionCategory: Double] { [:] }

    var budgets: [TransactionCategory: Double] = [:]
    func categoryBudgets() -> [CategoryBudget] {
        budgets.map { CategoryBudget(category: $0.key, monthlyLimit: $0.value) }
    }
    func setCategoryBudget(_ category: TransactionCategory, monthlyLimit: Double) { budgets[category] = monthlyLimit }
    func removeCategoryBudget(_ category: TransactionCategory) { budgets.removeValue(forKey: category) }

    var storedRecurring: [RecurringTransaction] = []
    func recurringTransactions() -> [RecurringTransaction] { storedRecurring }
    func addRecurringTransaction(_ transaction: RecurringTransaction) { storedRecurring.append(transaction) }
    func deleteRecurringTransaction(_ transaction: RecurringTransaction) { storedRecurring.removeAll { $0.id == transaction.id } }
    func setRecurringTransactionActive(_ transaction: RecurringTransaction, isActive: Bool) { transaction.isActive = isActive }
    func applyDueRecurringTransactions() -> Int { 0 }
}
