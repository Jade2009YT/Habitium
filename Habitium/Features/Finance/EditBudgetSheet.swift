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
    @State private var hasGoal: Bool
    @State private var goalAmountText: String
    @State private var goalDate: Date

    init(viewModel: FinanceViewModel) {
        self.viewModel = viewModel
        _budgetText = State(initialValue: String(format: "%.2f", viewModel.overview.monthlyBudget))
        _savingsText = State(initialValue: String(format: "%.2f", viewModel.overview.totalSavings))
        _hasGoal = State(initialValue: viewModel.savingsGoalAmount != nil)
        _goalAmountText = State(initialValue: viewModel.savingsGoalAmount.map { String(format: "%.2f", $0) } ?? "")
        _goalDate = State(initialValue: viewModel.savingsGoalDate ?? Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now)
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
                Section {
                    Toggle("Meta de ahorro", isOn: $hasGoal)
                    if hasGoal {
                        TextField("Monto objetivo", text: $goalAmountText).keyboardType(.decimalPad)
                        DatePicker("Fecha objetivo", selection: $goalDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Al estilo EveryDollar: define cuánto quieres ahorrar y para cuándo, y verás el progreso en Finanzas.")
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

                        if hasGoal, let goalAmount = Double(goalAmountText.replacingOccurrences(of: ",", with: ".")) {
                            viewModel.updateSavingsGoal(amount: goalAmount, date: goalDate)
                        } else if !hasGoal {
                            viewModel.updateSavingsGoal(amount: nil, date: nil)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
