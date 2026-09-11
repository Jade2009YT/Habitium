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
    private var remaining: Double { max(0, goalAmount - currentSavings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Meta de ahorro", symbol: "target", color: Theme.Colors.finance) {
                if let goalDate {
                    Text(goalDate, format: .dateTime.month(.abbreviated).year())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currentSavings, format: .currency(code: currencyCode))
                    .font(Theme.Fonts.metricSmall)
                    .contentTransition(.numericText())
                Text("de \(goalAmount.formatted(.currency(code: currencyCode)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressBar(value: progress, color: Theme.Colors.finance, height: 8)

            // Lo que falta y no solo el porcentaje: "te quedan 260 €" es
            // una cifra con la que se puede hacer algo; "52 %" no.
            Text(
                remaining > 0
                    ? "Te faltan \(remaining.formatted(.currency(code: currencyCode)))"
                    : "Meta conseguida. 🎉"
            )
            .font(.caption)
            .foregroundStyle(remaining > 0 ? .secondary : Theme.Colors.finance)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    SavingsGoalCard(currentSavings: 2400, goalAmount: 5000, goalDate: .now.addingTimeInterval(86400 * 200), currencyCode: "EUR")
        .padding()
}
