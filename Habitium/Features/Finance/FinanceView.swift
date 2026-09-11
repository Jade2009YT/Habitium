//
//  FinanceView.swift
//  Habitium
//
//  Finanzas: lo que queda este mes arriba, y debajo la meta de ahorro,
//  el desglose por categoría, los límites y los movimientos.
//
//  En tarjetas dentro de un ScrollView, como el resto de la app. Con
//  `List` cada tarjeta iba envuelta en una fila que había que disimular
//  con `listRowInsets`/`listRowBackground`, y el menú de "Editar
//  presupuesto" vivía escondido en `secondaryAction` de la barra, donde
//  no lo encontraba nadie. Ahora las acciones están en la tarjeta a la
//  que pertenecen.
//
//  Lo que se pierde al salir de `List` son las `swipeActions`, así que
//  eliminar un movimiento es mantener pulsado — igual que en Hábitos,
//  Medicación y Nutrición.
//

import SwiftUI

struct FinanceView: View {
    @Environment(AppDependencyContainer.self) private var container
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator
    @State private var viewModel: FinanceViewModel?
    @State private var showingAddTransaction = false
    @State private var showingEditBudget = false
    @State private var showingCategoryBudgets = false
    @State private var showingRecurring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let viewModel {
                    VStack(spacing: Theme.Layout.sectionSpacing) {
                        BudgetProgressView(overview: viewModel.overview)
                            .appearIn(0)

                        if let goalAmount = viewModel.savingsGoalAmount {
                            SavingsGoalCard(
                                currentSavings: viewModel.overview.totalSavings,
                                goalAmount: goalAmount,
                                goalDate: viewModel.savingsGoalDate,
                                currencyCode: viewModel.overview.currencyCode
                            )
                            .appearIn(1)
                        }

                        categoriesCard(viewModel).appearIn(2)

                        if viewModel.categoryBreakdown.contains(where: { $0.limit != nil }) {
                            limitsCard(viewModel).appearIn(3)
                        }

                        transactionsCard(viewModel).appearIn(4)
                        toolsCard().appearIn(5)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .themedBackground()
            .navigationTitle("Finanzas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingAddTransaction, onDismiss: { viewModel?.refresh() }) {
                if let viewModel { AddTransactionView(viewModel: viewModel) }
            }
            .sheet(isPresented: $showingEditBudget, onDismiss: { viewModel?.refresh() }) {
                if let viewModel { EditBudgetSheet(viewModel: viewModel) }
            }
            .sheet(isPresented: $showingCategoryBudgets, onDismiss: { viewModel?.refresh() }) {
                if let viewModel { CategoryBudgetsSheet(viewModel: viewModel) }
            }
            .sheet(isPresented: $showingRecurring, onDismiss: { viewModel?.refresh() }) {
                if let viewModel { RecurringTransactionsSheet(viewModel: viewModel) }
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

    // MARK: - Gastos por categoría

    private func categoriesCard(_ viewModel: FinanceViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Por categoría", symbol: "chart.pie.fill", color: Theme.Colors.finance) {
                Button("Límites") { showingCategoryBudgets = true }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.finance)
            }

            CategoryDonutChart(
                rows: viewModel.categoryBreakdown,
                currencyCode: viewModel.overview.currencyCode
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Límites por categoría

    private func limitsCard(_ viewModel: FinanceViewModel) -> some View {
        let rows = viewModel.categoryBreakdown.filter { $0.limit != nil }
        let pasados = rows.filter(\.isOverLimit).count

        return VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Límites", symbol: "gauge", color: Theme.Colors.finance) {
                if pasados > 0 {
                    Text("\(pasados) pasado\(pasados == 1 ? "" : "s")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.danger)
                }
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                limitRow(row, currencyCode: viewModel.overview.currencyCode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func limitRow(_ row: CategorySpendingRow, currencyCode: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                IconBadge(
                    symbol: row.category.symbolName,
                    color: row.isOverLimit ? Theme.Colors.danger : Theme.Colors.finance,
                    size: 26
                )
                Text(row.category.displayName)
                    .font(Theme.Fonts.rowTitle)
                Spacer(minLength: 8)
                if let limit = row.limit {
                    Text("\(row.spent.formatted(.currency(code: currencyCode))) / \(limit.formatted(.currency(code: currencyCode)))")
                        .font(.caption2)
                        .foregroundStyle(row.isOverLimit ? Theme.Colors.danger : .secondary)
                        .monospacedDigit()
                }
            }

            if let progress = row.progress {
                ProgressBar(
                    value: progress,
                    color: row.isOverLimit ? Theme.Colors.danger : Theme.Colors.finance,
                    height: 6
                )
            }
        }
    }

    // MARK: - Movimientos

    private func transactionsCard(_ viewModel: FinanceViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Movimientos del mes", symbol: "list.bullet", color: Theme.Colors.finance) {
                if !viewModel.transactions.isEmpty {
                    Text("\(viewModel.transactions.count)")
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.transactions.isEmpty {
                EmptyHint(symbol: "plus.circle", message: "Aún no hay movimientos este mes. Añade uno con el +.")
            } else {
                ForEach(Array(viewModel.transactions.enumerated()), id: \.element.id) { index, transaction in
                    if index > 0 { Divider() }
                    transactionRow(transaction, viewModel: viewModel)
                }

                Text("Mantén pulsado un movimiento para eliminarlo.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func transactionRow(_ transaction: Transaction, viewModel: FinanceViewModel) -> some View {
        let category = TransactionCategory(rawValue: transaction.category) ?? .other
        let isIncome = transaction.type == TransactionType.income.rawValue
        let currencyCode = viewModel.overview.currencyCode

        return HStack(spacing: 11) {
            IconBadge(
                symbol: category.symbolName,
                color: isIncome ? Theme.Colors.nutrition : Theme.Colors.finance,
                size: 26
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.note?.isEmpty == false ? transaction.note! : category.displayName)
                    .font(Theme.Fonts.rowTitle)
                    .lineLimit(1)
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // El ingreso en verde y el gasto en el color normal del
            // texto: pintar cada gasto de rojo haría que una pantalla
            // normal —donde casi todo son gastos— pareciera una alarma.
            Text((isIncome ? "+" : "−") + transaction.amount.formatted(.currency(code: currencyCode)))
                .font(Theme.Fonts.rowTitle)
                .monospacedDigit()
                .foregroundStyle(isIncome ? Theme.Colors.nutrition : .primary)
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteTransaction(transaction)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    // MARK: - Ajustes de la pantalla

    /// Antes esto vivía en el menú "…" de la barra de navegación, donde no
    /// lo encontraba nadie. Aquí abajo, como dos filas normales, está a la
    /// vista de quien baja hasta el final buscando justo eso.
    private func toolsCard() -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Ajustes de finanzas", symbol: "slider.horizontal.3", color: .secondary)

            Button {
                showingEditBudget = true
            } label: {
                toolRow(symbol: "target", title: "Presupuesto y meta de ahorro")
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                showingRecurring = true
            } label: {
                toolRow(symbol: "arrow.triangle.2.circlepath", title: "Gastos e ingresos fijos")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func toolRow(symbol: String, title: String) -> some View {
        HStack(spacing: 11) {
            IconBadge(symbol: symbol, color: Theme.Colors.finance, size: 26)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            DisclosureChevron()
        }
    }
}

#Preview {
    FinanceView()
        .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
        .environment(DeepLinkCoordinator())
}
