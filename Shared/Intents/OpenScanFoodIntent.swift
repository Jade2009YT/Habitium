//
//  OpenScanFoodIntent.swift
//  Habitium (shared between the app and widget extension targets)
//
//  Interactive-widget button on the nutrition widget: opens the app
//  straight into the "add meal" flow. Runs in the app process because
//  openAppWhenRun is true, so it can hand off through a queued deep link
//  that MainTabView consumes on launch/foreground.
//

import AppIntents

struct OpenScanFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Escanear comida"
    static var description = IntentDescription("Abre Habitium para registrar una comida con la cámara o texto.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.writePendingDeepLink(.scanFood)
        return .result()
    }
}
