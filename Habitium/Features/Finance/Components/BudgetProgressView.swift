//
//  BudgetProgressView.swift
//  Habitium
//
//  Visual summary card: total savings, available to spend, and a progress
//  bar for the percentage of the monthly budget consumed.
//

import SwiftUI

struct BudgetProgressView: View {
    let overview: FinanceOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Ahorro total").font(.caption).foregroundStyle(.secondary)
                    Text(overview.totalSavings, format: .currency(code: overview.currencyCode))
                        .font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Disponible este mes").font(.caption).foregroundStyle(.secondary)
                    Text(overview.availableToSpend, format: .currency(code: overview.currencyCode))
                        .font(.title3.bold())
                        .foregroundStyle(overview.isOverBudget ? Theme.Colors.danger : Theme.Colors.finance)
                }
            }

            ProgressView(value: overview.spentProgress) {
                HStack {
                    Text("Presupuesto usado")
                    Spacer()
                    Text("\(Int(overview.spentProgress * 100))%")
                }
                .font(.caption)
            }
            .tint(overview.isOverBudget ? Theme.Colors.danger : Theme.Colors.finance)

            Text("\(overview.monthlySpent.formatted(.currency(code: overview.currencyCode))) de \(overview.monthlyBudget.formatted(.currency(code: overview.currencyCode)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
}

#Preview {
    BudgetProgressView(overview: .init(availableToSpend: 350, monthlyBudget: 1000, monthlySpent: 650, totalSavings: 2400, currencyCode: "USD"))
        .padding()
}
