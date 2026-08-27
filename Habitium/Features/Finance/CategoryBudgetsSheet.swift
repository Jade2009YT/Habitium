//
//  CategoryBudgetsSheet.swift
//  Habitium
//
//  Set a monthly limit per category — envelope budgeting, the standout
//  Goodbudget/Monarch Money feature. A category without a limit is simply
//  tracked, not capped.
//

import SwiftUI

struct CategoryBudgetsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FinanceViewModel

    @State private var limitTexts: [TransactionCategory: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(TransactionCategory.allCases.filter { $0 != .salary }) { category in
                        HStack {
                            Label(category.displayName, systemImage: category.symbolName)
                            Spacer()
                            TextField("Sin límite", text: binding(for: category))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                } footer: {
                    Text("Deja el campo vacío para no poner límite a esa categoría.")
                }
            }
            .navigationTitle("Presupuesto por categoría")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func binding(for category: TransactionCategory) -> Binding<String> {
        Binding(
            get: { limitTexts[category, default: ""] },
            set: { limitTexts[category] = $0 }
        )
    }

    private func loadExisting() {
        for row in viewModel.categoryBreakdown {
            if let limit = row.limit {
                limitTexts[row.category] = String(format: "%.0f", limit)
            }
        }
    }

    private func save() {
        for category in TransactionCategory.allCases {
            let text = limitTexts[category, default: ""].replacingOccurrences(of: ",", with: ".")
            if let value = Double(text), value > 0 {
                viewModel.setCategoryLimit(category, limit: value)
            } else if text.isEmpty {
                viewModel.removeCategoryLimit(category)
            }
        }
    }
}
