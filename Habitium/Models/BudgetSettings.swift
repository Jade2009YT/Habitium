//
//  BudgetSettings.swift
//  Habitium
//
//  Configurable monthly spending budget and running total savings. Actual
//  income/expenses live in Transaction rows; this model just holds the
//  user-set target and the savings balance the user maintains manually.
//

import Foundation
import SwiftData

@Model
final class BudgetSettings {
    var id: UUID
    var monthlyBudget: Double
    var totalSavings: Double
    var currencyCode: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        monthlyBudget: Double = 1000,
        totalSavings: Double = 0,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        updatedAt: Date = .now
    ) {
        self.id = id
        self.monthlyBudget = monthlyBudget
        self.totalSavings = totalSavings
        self.currencyCode = currencyCode
        self.updatedAt = updatedAt
    }
}
