//
//  HabitiumApp.swift
//  Habitium
//
//  App entry point. Builds the SwiftData ModelContainer once and injects it
//  (plus the composed repositories) into the SwiftUI environment, keeping
//  the presentation layer (Views/ViewModels) decoupled from persistence.
//

import SwiftData
import SwiftUI

@main
struct HabitiumApp: App {

    // Owns the persistence stack for the whole app lifetime.
    private let persistence = PersistenceController.shared

    // Root dependency container (Clean Architecture composition root).
    @State private var container: AppDependencyContainer
    @State private var deepLinkCoordinator = DeepLinkCoordinator()
    @State private var authManager = AppleSignInManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let persistence = PersistenceController.shared
        _container = State(initialValue: AppDependencyContainer(modelContext: persistence.container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(deepLinkCoordinator)
                .environment(authManager)
                .task {
                    NotificationScheduler.shared.requestAuthorizationIfNeeded()
                    PendingActionProcessor.processPendingTaskCompletions(using: container.plannerRepository)
                    container.financeRepository.applyDueRecurringTransactions()
                    deepLinkCoordinator.checkForPendingLink()
                }
        }
        .modelContainer(persistence.container)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            PendingActionProcessor.processPendingTaskCompletions(using: container.plannerRepository)
            container.financeRepository.applyDueRecurringTransactions()
            deepLinkCoordinator.checkForPendingLink()
        }
    }
}
