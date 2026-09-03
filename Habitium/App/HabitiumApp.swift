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
    @State private var emailAuth = SupabaseAuthManager()
    @State private var localAccess = LocalAccessManager()
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
                .environment(emailAuth)
                .environment(localAccess)
                .environment(lockManager)
                .task {
                    NotificationScheduler.shared.requestAuthorizationIfNeeded()
                    WatchConnectivityBridge.shared.onWorkoutSetsReceived = { sets in
                        container.workoutRepository.save(sets)
                    }
                    // Reuses emailAuth's own SupabaseClient — see
                    // CloudSyncService's doc comment on why. The first
                    // actual sync pass runs from RootView, right after
                    // emailAuth.restoreSession() confirms whether there's
                    // a signed-in account to sync at all.
                    CloudSyncService.shared.authManager = emailAuth
                    _ = WatchConnectivityBridge.shared // activates the WCSession so the Watch app gets synced
                    PendingActionProcessor.processPendingTaskCompletions(using: container.plannerRepository)
                    PendingActionProcessor.processPendingMedicationDoses(using: container.medicationRepository)
                    container.financeRepository.applyDueRecurringTransactions()
                    deepLinkCoordinator.checkForPendingLink()
                    lockManager.lockIfNeeded()
                    // Cuenta el día y actualiza la racha. Es idempotente:
                    // abrir la app diez veces hoy solo cuenta una.
                    container.progressionRepository.registerDailyLogin(on: .now)
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
                // Volver a primer plano al día siguiente sin haber cerrado
                // la app también cuenta como el día nuevo — si no, quien
                // nunca la cierra perdería la racha.
                container.progressionRepository.registerDailyLogin(on: .now)
                // No-op if not signed in via Supabase (see CloudSyncService's
                // Apple-only disclaimer) or already mid-sync.
                Task { await CloudSyncService.shared.syncAll(context: persistence.container.mainContext) }
            case .background:
                lockManager.lockOnBackground()
            default:
                break
            }
        }
    }
}
