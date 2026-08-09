//
//  OpenAddExpenseIntent.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Interactive-widget button on the finance widget: opens the app into
//  the "add transaction" flow.
//

import AppIntents

struct OpenAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Abre Habitium para registrar un ingreso o gasto.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.writePendingDeepLink(.addExpense)
        return .result()
    }
}
