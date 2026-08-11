//
//  RecurringTransactionsSheet.swift
//  Habitium
//
//  Manage fixed monthly bills/income (Monarch Money/EveryDollar-style).
//  Each active row auto-logs a real Transaction once its day of the month
//  arrives — see FinanceRepository.applyDueRecurringTransactions.
//

import SwiftUI

struct RecurringTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FinanceViewModel

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.recurringTransactions.isEmpty {
                    Text("Sin gastos o ingresos recurrentes todavía.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.recurringTransactions) { recurring in
                        recurringRow(recurring)
                            .swipeActions {
                                Button(role: .destructive) {
                                    viewModel.deleteRecurringTransaction(recurring)
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Gastos recurrentes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddRecurringTransactionSheet(viewModel: viewModel)
            }
        }
    }

    private func recurringRow(_ recurring: RecurringTransaction) -> some View {
        let category = TransactionCategory(rawValue: recurring.category) ?? .other
        let isIncome = recurring.type == TransactionType.income.rawValue

        return HStack {
            Image(systemName: category.symbolName)
                .foregroundStyle(isIncome ? Theme.Colors.finance : Theme.Colors.danger)
            VStack(alignment: .leading) {
                Text(recurring.name).font(.subheadline.bold())
                Text("Día \(recurring.dayOfMonth) de cada mes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((isIncome ? "+" : "-") + recurring.amount.formatted(.currency(code: viewModel.overview.currencyCode)))
                .font(.subheadline)
            Toggle("", isOn: Binding(
                get: { recurring.isActive },
                set: { viewModel.setRecurringTransactionActive(recurring, isActive: $0) }
            ))
            .labelsHidden()
        }
    }
}

private struct AddRecurringTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: FinanceViewModel

    @State private var name = ""
    @State private var amountText = ""
    @State private var type: TransactionType = .expense
    @State private var category: TransactionCategory = .services
    @State private var dayOfMonth = 1

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (ej: Alquiler, Netflix)", text: $name)
                Picker("Tipo", selection: $type) {
                    Text("Gasto").tag(TransactionType.expense)
                    Text("Ingreso").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                TextField("Monto", text: $amountText).keyboardType(.decimalPad)
                Picker("Categoría", selection: $category) {
                    ForEach(TransactionCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                    }
                }
                Stepper("Día del mes: \(dayOfMonth)", value: $dayOfMonth, in: 1...28)
            }
            .navigationTitle("Nuevo recurrente")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
                        viewModel.addRecurringTransaction(name: name, amount: amount, type: type, category: category, dayOfMonth: dayOfMonth)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Double(amountText.replacingOccurrences(of: ",", with: ".")) == nil)
                }
            }
        }
    }
}
