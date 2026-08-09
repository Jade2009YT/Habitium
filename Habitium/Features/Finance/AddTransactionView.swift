//
//  AddTransactionView.swift
//  Habitium
//
//  Quick-add sheet for an income/expense movement, categorized as
//  comida/ocio/ahorro/servicios/etc.
//

import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FinanceViewModel

    @State private var type: TransactionType = .expense
    @State private var category: TransactionCategory = .food
    @State private var amountText = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $type) {
                    Text("Gasto").tag(TransactionType.expense)
                    Text("Ingreso").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)

                TextField("Monto", text: $amountText)
                    .keyboardType(.decimalPad)

                Picker("Categoría", selection: $category) {
                    ForEach(TransactionCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                    }
                }

                TextField("Nota (opcional)", text: $note)
            }
            .navigationTitle("Nuevo movimiento")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
                        viewModel.addTransaction(amount: amount, type: type, category: category, note: note.isEmpty ? nil : note)
                        dismiss()
                    }
                    .disabled(Double(amountText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }
}
