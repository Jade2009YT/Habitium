//
//  EditBudgetSheet.swift
//  Habitium
//

import SwiftUI

struct EditBudgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FinanceViewModel

    @State private var budgetText: String
    @State private var savingsText: String

    init(viewModel: FinanceViewModel) {
        self.viewModel = viewModel
        _budgetText = State(initialValue: String(format: "%.2f", viewModel.overview.monthlyBudget))
        _savingsText = State(initialValue: String(format: "%.2f", viewModel.overview.totalSavings))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Presupuesto mensual") {
                    TextField("Monto", text: $budgetText).keyboardType(.decimalPad)
                }
                Section("Ahorro total") {
                    TextField("Monto", text: $savingsText).keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Editar finanzas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let budget = Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? viewModel.overview.monthlyBudget
                        let savings = Double(savingsText.replacingOccurrences(of: ",", with: ".")) ?? viewModel.overview.totalSavings
                        viewModel.updateBudget(monthlyBudget: budget, totalSavings: savings)
                        dismiss()
                    }
                }
            }
        }
    }
}
