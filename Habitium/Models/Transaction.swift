//
//  Transaction.swift
//  Habitium
//
//  SwiftData model for a single income/expense movement shown in
//  FinanceView.
//

import Foundation
import SwiftData

enum TransactionType: String, Codable, CaseIterable {
    case income
    case expense
}

enum TransactionCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case leisure
    case savings
    case services
    case transport
    case health
    case salary
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Comida"
        case .leisure: return "Ocio"
        case .savings: return "Ahorro"
        case .services: return "Servicios"
        case .transport: return "Transporte"
        case .health: return "Salud"
        case .salary: return "Salario"
        case .other: return "Otro"
        }
    }

    var symbolName: String {
        switch self {
        case .food: return "fork.knife"
        case .leisure: return "gamecontroller.fill"
        case .savings: return "banknote.fill"
        case .services: return "bolt.fill"
        case .transport: return "car.fill"
        case .health: return "heart.fill"
        case .salary: return "dollarsign.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

@Model
final class Transaction {
    var id: UUID
    var amount: Double
    var type: TransactionType.RawValue
    var category: TransactionCategory.RawValue
    var note: String?
    var date: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        type: TransactionType,
        category: TransactionCategory,
        note: String? = nil,
        date: Date = .now
    ) {
        self.id = id
        self.amount = amount
        self.type = type.rawValue
        self.category = category.rawValue
        self.note = note
        self.date = date
    }

    /// Signed amount: positive for income, negative for expense — convenient
    /// for balance sums.
    var signedAmount: Double {
        type == TransactionType.income.rawValue ? amount : -amount
    }
}
