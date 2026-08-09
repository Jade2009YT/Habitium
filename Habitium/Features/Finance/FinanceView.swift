//
//  FinanceView.swift
//  Habitium
//
//  Finanzas Personales tab: savings, available budget, quick transaction
//  log, and the spent-percentage progress bar.
//

import SwiftUI

struct FinanceView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator
    @State private var viewModel: FinanceViewModel?
    @State private var showingAddTransaction = false
    @State private var showingEditBudget = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List {
                        Section {
                            BudgetProgressView(overview: viewModel.overview)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        Section("Movimientos de este mes") {
                            if viewModel.transactions.isEmpty {
                                Text("Aún no hay movimientos este mes.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(viewModel.transactions) { transaction in
                                    transactionRow(transaction)
                                        .swipeActions {
                                            Button(role: .destructive) {
                                                viewModel.deleteTransaction(transaction)
                                            } label: {
                                                Label("Eliminar", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Finanzas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Editar presupuesto y ahorro") {
                        showingEditBudget = true
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction, onDismiss: { viewModel?.refresh() }) {
                if let viewModel { AddTransactionView(viewModel: viewModel) }
            }
            .sheet(isPresented: $showingEditBudget, onDismiss: { viewModel?.refresh() }) {
                if let viewModel { EditBudgetSheet(viewModel: viewModel) }
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = FinanceViewModel(container: container)
                } else {
                    viewModel?.refresh()
                }
            }
            .onChange(of: deepLinkCoordinator.pendingLink) { _, newValue in
                guard newValue == .addExpense else { return }
                showingAddTransaction = true
                deepLinkCoordinator.consume()
            }
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        let category = TransactionCategory(rawValue: transaction.category) ?? .other
        let isIncome = transaction.type == TransactionType.income.rawValue

        return HStack {
            Image(systemName: category.symbolName)
                .foregroundStyle(isIncome ? Theme.Colors.finance : Theme.Colors.danger)
            VStack(alignment: .leading) {
                Text(transaction.note?.isEmpty == false ? transaction.note! : category.displayName)
                    .font(.subheadline.bold())
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((isIncome ? "+" : "-") + transaction.amount.formatted(.currency(code: viewModel?.overview.currencyCode ?? "USD")))
                .foregroundStyle(isIncome ? Theme.Colors.finance : .primary)
        }
    }
}

#Preview {
    FinanceView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
        .environment(DeepLinkCoordinator())
}
