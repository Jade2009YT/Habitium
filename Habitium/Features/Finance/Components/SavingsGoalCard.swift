//
//  SavingsGoalCard.swift
//  Habitium
//
//  Progress toward an optional savings goal (amount + target date) —
//  EveryDollar-style. Hidden entirely when no goal is set.
//

import SwiftUI

struct SavingsGoalCard: View {
    let currentSavings: Double
    let goalAmount: Double
    let goalDate: Date?
    let currencyCode: String

    private var progress: Double { goalAmount > 0 ? min(currentSavings / goalAmount, 1.0) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Meta de ahorro", systemImage: "target")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if let goalDate {
                    Text(goalDate, format: .dateTime.month(.abbreviated).year())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(currentSavings, format: .currency(code: currencyCode)).font(.title3.bold())
                Text("de \(goalAmount.formatted(.currency(code: currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(Theme.Colors.finance)
        }
        .cardStyle()
    }
}

#Preview {
    SavingsGoalCard(currentSavings: 2400, goalAmount: 5000, goalDate: .now.addingTimeInterval(86400 * 200), currencyCode: "EUR")
        .padding()
}
