//
//  CategoryDonutChart.swift
//  Habitium
//
//  Spending-by-category donut, the signature visual of Monarch Money's
//  budget screen — finally gives the Finance tab's chart.pie.fill icon
//  something to point at.
//

import Charts
import SwiftUI

private let categoryPalette: [TransactionCategory: Color] = [
    .food: .orange,
    .leisure: .purple,
    .savings: Theme.Colors.finance,
    .services: .blue,
    .transport: .teal,
    .health: .pink,
    .salary: .green,
    .other: .gray
]

struct CategoryDonutChart: View {
    let rows: [CategorySpendingRow]
    let currencyCode: String

    private var total: Double { rows.reduce(0) { $0 + $1.spent } }

    var body: some View {
        if rows.isEmpty || total <= 0 {
            Text("Aún no hay gastos este mes para desglosar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 18) {
                Chart(rows) { row in
                    SectorMark(angle: .value("Gastado", row.spent), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(categoryPalette[row.category] ?? .gray)
                        .cornerRadius(3)
                }
                .frame(width: 110, height: 110)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text(total, format: .currency(code: currencyCode))
                            .font(.caption.bold())
                        Text("total").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.prefix(5)) { row in
                        HStack(spacing: 6) {
                            Circle().fill(categoryPalette[row.category] ?? .gray).frame(width: 7, height: 7)
                            Text(row.category.displayName).font(.caption2)
                            Spacer()
                            Text(row.spent, format: .currency(code: currencyCode)).font(.caption2.bold())
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    CategoryDonutChart(rows: [
        .init(category: .food, spent: 220, limit: 300),
        .init(category: .leisure, spent: 90, limit: 100),
        .init(category: .services, spent: 140, limit: nil)
    ], currencyCode: "EUR")
    .padding()
}
