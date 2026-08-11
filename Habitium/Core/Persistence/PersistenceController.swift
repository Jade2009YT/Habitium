//
//  PersistenceController.swift
//  Habitium
//
//  Owns the single SwiftData ModelContainer for the app. The store lives in
//  the shared App Group container so it is physically available to the
//  widget extension too (widgets themselves read lightweight JSON
//  snapshots via SharedDataStore for reliability — see that file — but
//  keeping the store itself in the App Group leaves the door open for the
//  extension to query it directly in the future).
//
//  100% local storage: no CloudKit, no remote sync, nothing leaves the
//  device.
//

import Foundation
import SwiftData

final class PersistenceController {

    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            FoodEntry.self,
            NutritionGoal.self,
            WeightEntry.self,
            PlannerTask.self,
            PlannerEvent.self,
            PlannerNote.self,
            Transaction.self,
            BudgetSettings.self,
            CategoryBudget.self,
            UserSettings.self
        ])

        let configuration: ModelConfiguration
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupID)?
            .appendingPathComponent("Habitium.sqlite") {
            configuration = ModelConfiguration(schema: schema, url: groupURL)
        } else {
            // Fallback for previews / simulators without the App Group
            // entitlement configured yet — keeps the app runnable while the
            // Apple Developer account / provisioning is being set up.
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("No se pudo crear el ModelContainer de SwiftData: \(error)")
        }

        Task { @MainActor in
            SeedData.seedIfNeeded(context: container.mainContext)
        }
    }

    /// In-memory container for SwiftUI previews and unit tests.
    @MainActor
    static func preview(seeded: Bool = true) -> PersistenceController {
        let controller = PersistenceController(inMemory: true)
        if seeded {
            SeedData.seedIfNeeded(context: controller.container.mainContext, forcePreviewData: true)
        }
        return controller
    }

    private init(inMemory: Bool) {
        let schema = Schema([
            FoodEntry.self,
            NutritionGoal.self,
            WeightEntry.self,
            PlannerTask.self,
            PlannerEvent.self,
            PlannerNote.self,
            Transaction.self,
            BudgetSettings.self,
            CategoryBudget.self,
            UserSettings.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("No se pudo crear el ModelContainer en memoria: \(error)")
        }
    }
}
