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
    @State private var lockManager = AppLockManager()
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
                .environment(lockManager)
                .task {
                    NotificationScheduler.shared.requestAuthorizationIfNeeded()
                    _ = WatchConnectivityBridge.shared // activates the WCSession so the Watch app gets synced
                    PendingActionProcessor.processPendingTaskCompletions(using: container.plannerRepository)
                    PendingActionProcessor.processPendingMedicationDoses(using: container.medicationRepository)
                    container.financeRepository.applyDueRecurringTransactions()
                    deepLinkCoordinator.checkForPendingLink()
                    lockManager.lockIfNeeded()
                }
        }
        .modelContainer(persistence.container)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                PendingActionProcessor.processPendingTaskCompletions(using: container.plannerRepository)
                PendingActionProcessor.processPendingMedicationDoses(using: container.medicationRepository)
                container.financeRepository.applyDueRecurringTransactions()
                deepLinkCoordinator.checkForPendingLink()
                lockManager.lockIfNeeded()
            case .background:
                lockManager.lockOnBackground()
            default:
                break
            }
        }
    }
}
