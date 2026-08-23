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
//  Encrypted at rest: the store (and its SQLite -wal/-shm sidecar files)
//  is set to NSFileProtectionComplete, iOS's strongest Data Protection
//  class — the files are unreadable, even to someone with the raw disk
//  image, until the device has been unlocked with its passcode/biometrics
//  at least once after boot, and become unreadable again the moment the
//  device locks. Combined with AppLockManager (which re-locks the app on
//  every background) this means Habitium's data is never sitting
//  decrypted while nobody's actively using the app. Trade-off: no
//  background task should try to touch the database while the device is
//  locked — this app doesn't need to, everything happens in the
//  foreground or via the widget's separate UserDefaults snapshot.
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
            RecurringTransaction.self,
            Medication.self,
            MedicationDoseLog.self,
            UserSettings.self
        ])

        let configuration: ModelConfiguration
        var storeURL: URL?
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfiguration.appGroupID)?
            .appendingPathComponent("Habitium.sqlite") {
            configuration = ModelConfiguration(schema: schema, url: groupURL)
            storeURL = groupURL
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

        if let storeURL {
            Self.applyStrongestFileProtection(storeURL: storeURL)
        }

        Task { @MainActor in
            SeedData.seedIfNeeded(context: container.mainContext)
        }
    }

    /// Sets NSFileProtectionComplete on the store file and its SQLite
    /// -wal/-shm sidecar files. Safe to call even if a sidecar doesn't
    /// exist yet (setAttributes just fails silently for that one).
    private static func applyStrongestFileProtection(storeURL: URL) {
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let path = storeURL.path + suffix
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try? FileManager.default.setAttributes(attributes, ofItemAtPath: path)
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
            RecurringTransaction.self,
            Medication.self,
            MedicationDoseLog.self,
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
