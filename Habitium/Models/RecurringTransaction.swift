//
//  RecurringTransaction.swift
//  Habitium
//
//  A fixed monthly income/expense (rent, subscriptions, salary...) that
//  gets auto-logged as a real Transaction once its day of the month
//  arrives — the Monarch Money/EveryDollar "recurring bills" idea.
//  lastAppliedMonth guards against double-logging the same month.
//

import Foundation
import SwiftData

@Model
final class RecurringTransaction {
    var id: UUID
    var name: String
    var amount: Double
    var type: TransactionType.RawValue
    var category: TransactionCategory.RawValue
    /// Day of the month (1-28, kept short to be valid in every month) this
    /// should be auto-logged on.
    var dayOfMonth: Int
    var isActive: Bool
    /// Start-of-month date this was last auto-applied for, so it only logs
    /// once per month even if the app opens multiple times that day.
    var lastAppliedMonth: Date?
    var createdAt: Date
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        type: TransactionType,
        category: TransactionCategory,
        dayOfMonth: Int,
        isActive: Bool = true,
        lastAppliedMonth: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.type = type.rawValue
        self.category = category.rawValue
        self.dayOfMonth = min(max(dayOfMonth, 1), 28)
        self.isActive = isActive
        self.lastAppliedMonth = lastAppliedMonth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
