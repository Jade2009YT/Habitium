//
//  CategoryBudget.swift
//  Habitium
//
//  Per-category monthly spending limit — the "envelope budgeting" idea
//  from Goodbudget/Monarch Money, layered on top of the single overall
//  BudgetSettings.monthlyBudget. One row per TransactionCategory that the
//  user has chosen to cap; categories without a row are simply not
//  tracked against a limit.
//

import Foundation
import SwiftData

@Model
final class CategoryBudget {
    var id: UUID
    var category: TransactionCategory.RawValue
    var monthlyLimit: Double
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(id: UUID = UUID(), category: TransactionCategory, monthlyLimit: Double, updatedAt: Date = .now) {
        self.id = id
        self.category = category.rawValue
        self.monthlyLimit = monthlyLimit
        self.updatedAt = updatedAt
    }
}
