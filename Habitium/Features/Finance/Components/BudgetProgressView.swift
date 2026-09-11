//
//  BudgetProgressView.swift
//  Habitium
//
//  La tarjeta principal de Finanzas: lo que queda este mes, en grande,
//  con el ahorro y el porcentaje gastado debajo.
//
//  Manda "lo que te queda" y no "lo que llevas gastado" a propósito: es
//  la cifra con la que se decide si te puedes permitir algo ahora mismo,
//  que es para lo que se abre esta pantalla. Lo gastado está, pero en
//  letra pequeña.
//
//  Usa `rawSpentProgress` (sin limitar) y no `spentProgress`: con el
//  limitado la barra nunca pasaría de 1 y el rojo de "te has pasado del
//  presupuesto" no llegaría a aparecer.
//

import SwiftUI

struct BudgetProgressView: View {
    let overview: FinanceOverview

    private var percent: Int { Int((overview.rawSpentProgress * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Este mes", symbol: "eurosign.circle.fill", color: Theme.Colors.finance) {
                if overview.isOverBudget {
                    Label("Te has pasado", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.danger)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(overview.availableToSpend, format: .currency(code: overview.currencyCode))
                    .font(Theme.Fonts.metric)
                    .foregroundStyle(overview.isOverBudget ? Theme.Colors.danger : .primary)
                    .contentTransition(.numericText())
                Text("disponible para gastar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressBar(
                value: overview.rawSpentProgress,
                color: Theme.Colors.finance,
                height: 9
            )

            HStack(spacing: 6) {
                Text("\(percent) % del presupuesto")
                    .font(.caption)
                    .foregroundStyle(overview.isOverBudget ? Theme.Colors.danger : .secondary)
                Spacer(minLength: 8)
                Text("\(overview.monthlySpent.formatted(.currency(code: overview.currencyCode))) de \(overview.monthlyBudget.formatted(.currency(code: overview.currencyCode)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack(spacing: 10) {
                IconBadge(symbol: "banknote.fill", color: Theme.Colors.finance, size: 26)
                Text("Ahorro total")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(overview.totalSavings, format: .currency(code: overview.currencyCode))
                    .font(Theme.Fonts.rowTitle)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    BudgetProgressView(overview: .init(availableToSpend: 350, monthlyBudget: 1000, monthlySpent: 650, totalSavings: 2400, currencyCode: "EUR"))
        .padding()
}
