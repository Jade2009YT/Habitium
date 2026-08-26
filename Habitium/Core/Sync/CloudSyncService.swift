//
//  CloudSyncService.swift
//  Habitium
//
//  Fase 2: mirrors this account's data to Supabase Postgres (see
//  supabase/schema.sql) so it's the same on every device signed into the
//  same account — not just this iPhone anymore.
//
//  ⚠️ Only works for accounts signed in via Supabase email/password
//  (SupabaseAuthManager). Sign in with Apple has no Supabase session and
//  therefore no `auth.uid()` for Postgres RLS to scope rows to — an
//  Apple-only sign-in stays exactly as before: 100% local, nothing
//  leaves the device. Unifying the two (Apple as a Supabase OAuth
//  provider) is a real option later, just not done here.
//
//  How it works: `syncAll` does a full reconcile per table — pulls every
//  remote row for the signed-in user, merges "gana el más reciente" (by
//  `updatedAt`, which only the device that made a real edit ever
//  changes — see the models' updatedAt fields and each repository's
//  mutation methods), then pushes every local row back up. Deletions are
//  handled separately via PendingCloudDeletion tombstones, drained first
//  on every pass — otherwise a deleted local row would just get pulled
//  right back down as if it were new.
//
//  Deliberately a full reconcile, not a delta sync: at this app's scale
//  (one person, occasional cross-device sync, not real-time
//  collaboration) re-sending everything every time is cheap and, more
//  importantly, much simpler to get right without a compiler to check it
//  against than tracking per-row dirty state.
//

import Foundation
import Observation
import SwiftData
import Supabase

@MainActor
@Observable
final class CloudSyncService {

    static let shared = CloudSyncService()
    private init() {}

    /// Wired once from HabitiumApp — CloudSyncService reuses this exact
    /// SupabaseAuthManager instance's client rather than creating its
    /// own, so every Postgrest request automatically carries the
    /// signed-in session's token (see SupabaseAuthManager.client's doc).
    var authManager: SupabaseAuthManager?

    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?

    private var client: SupabaseClient? { authManager?.client }

    func syncAll(context: ModelContext) async {
        guard let client, authManager?.isSignedIn == true else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        await flushPendingDeletions(client: client, context: context)

        // Parents before children, so a just-pulled/just-pushed parent
        // row already exists (locally and in the cloud) before its
        // children try to reference it.
        await syncHabits(client: client, context: context)
        await syncHabitLogs(client: client, context: context)
        await syncWorkoutSets(client: client, context: context)

        await syncFoodEntries(client: client, context: context)
        await syncWeightEntries(client: client, context: context)
        await syncNutritionGoal(client: client, context: context)

        await syncPlannerTasks(client: client, context: context)
        await syncPlannerEvents(client: client, context: context)
        await syncPlannerNotes(client: client, context: context)

        await syncTransactions(client: client, context: context)
        await syncCategoryBudgets(client: client, context: context)
        await syncRecurringTransactions(client: client, context: context)
        await syncBudgetSettings(client: client, context: context)

        await syncMedications(client: client, context: context)
        await syncMedicationDoseLogs(client: client, context: context)

        await syncUserSettings(client: client, context: context)

        lastSyncedAt = .now
    }

    // MARK: - Tombstones

    private func flushPendingDeletions(client: SupabaseClient, context: ModelContext) async {
        let pending = (try? context.fetch(FetchDescriptor<PendingCloudDeletion>())) ?? []
        guard !pending.isEmpty else { return }
        for tombstone in pending {
            let succeeded = await CloudSyncTransport.delete(id: tombstone.recordID, table: tombstone.table, client: client)
            if succeeded {
                context.delete(tombstone)
            }
        }
        try? context.save()
    }

    // MARK: - Generic reconcile (every list-type table)

    private func reconcile<Local: PersistentModel, DTO: Codable & Sendable>(
        table: String,
        client: SupabaseClient,
        context: ModelContext,
        fetchLocal: () -> [Local],
        localID: (Local) -> UUID,
        localUpdatedAt: (Local) -> Date,
        dtoID: (DTO) -> UUID,
        dtoUpdatedAt: (DTO) -> Date,
        makeLocal: (DTO) -> Local,
        applyRemote: (DTO, Local) -> Void,
        toDTO: (Local) -> DTO
    ) async {
        let remoteRows: [DTO] = await CloudSyncTransport.fetchAll(table: table, client: client)
        var localByID = Dictionary(uniqueKeysWithValues: fetchLocal().map { (localID($0), $0) })

        for dto in remoteRows {
            let id = dtoID(dto)
            if let existing = localByID[id] {
                if dtoUpdatedAt(dto) > localUpdatedAt(existing) {
                    applyRemote(dto, existing)
                }
            } else {
                let created = makeLocal(dto)
                context.insert(created)
                localByID[id] = created
            }
        }
        try? context.save()

        let toPush = fetchLocal().map(toDTO)
        await CloudSyncTransport.upsert(toPush, table: table, client: client)
    }

    // MARK: - Hábitos

    private func syncHabits(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "habits",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<Habit>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                Habit(
                    id: dto.id,
                    name: dto.name,
                    symbolName: dto.symbolName,
                    kind: HabitKind(rawValue: dto.kind) ?? .checkbox,
                    targetValue: dto.targetValue,
                    goalDirection: HabitGoalDirection(rawValue: dto.goalDirection) ?? .atLeast,
                    unit: dto.unit,
                    isActive: dto.isActive,
                    sortOrder: dto.sortOrder,
                    createdAt: dto.createdAt,
                    linkedToWorkouts: dto.linkedToWorkouts,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.name = dto.name
                local.symbolName = dto.symbolName
                local.kind = dto.kind
                local.targetValue = dto.targetValue
                local.goalDirection = dto.goalDirection
                local.unit = dto.unit
                local.isActive = dto.isActive
                local.sortOrder = dto.sortOrder
                local.linkedToWorkouts = dto.linkedToWorkouts
                local.updatedAt = dto.updatedAt
            },
            toDTO: { habit in
                HabitDTO(
                    id: habit.id,
                    name: habit.name,
                    symbolName: habit.symbolName,
                    kind: habit.kind,
                    targetValue: habit.targetValue,
                    goalDirection: habit.goalDirection,
                    unit: habit.unit,
                    isActive: habit.isActive,
                    sortOrder: habit.sortOrder,
                    linkedToWorkouts: habit.linkedToWorkouts,
                    createdAt: habit.createdAt,
                    updatedAt: habit.updatedAt
                )
            }
        )
    }

    private func syncHabitLogs(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "habit_logs",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<HabitLog>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                HabitLog(id: dto.id, habitID: dto.habitID, date: dto.date, isCompleted: dto.isCompleted, value: dto.value, updatedAt: dto.updatedAt)
            },
            applyRemote: { dto, local in
                local.habitID = dto.habitID
                local.date = dto.date
                local.isCompleted = dto.isCompleted
                local.value = dto.value
                local.updatedAt = dto.updatedAt
            },
            toDTO: { log in
                HabitLogDTO(id: log.id, habitID: log.habitID, date: log.date, isCompleted: log.isCompleted, value: log.value, updatedAt: log.updatedAt)
            }
        )
    }

    // MARK: - Entrenamientos

    private func syncWorkoutSets(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "workout_sets",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                WorkoutSet(id: dto.id, exerciseName: dto.exerciseName, reps: dto.reps, date: dto.date, updatedAt: dto.updatedAt)
            },
            applyRemote: { dto, local in
                local.exerciseName = dto.exerciseName
                local.reps = dto.reps
                local.date = dto.date
                local.updatedAt = dto.updatedAt
            },
            toDTO: { set in
                WorkoutSetDTO(id: set.id, exerciseName: set.exerciseName, reps: set.reps, date: set.date, updatedAt: set.updatedAt)
            }
        )
    }

    // MARK: - Nutrición

    private func syncFoodEntries(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "food_entries",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                // Photo (imageData) never syncs — see supabase/README.md.
                FoodEntry(
                    id: dto.id,
                    name: dto.name,
                    date: dto.date,
                    mealType: MealType(rawValue: dto.mealType) ?? .breakfast,
                    source: MealSource(rawValue: dto.source) ?? .manual,
                    calories: dto.calories,
                    proteinGrams: dto.proteinGrams,
                    carbsGrams: dto.carbsGrams,
                    fatGrams: dto.fatGrams,
                    notes: dto.notes,
                    analyzedBy: dto.analyzedBy,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.name = dto.name
                local.date = dto.date
                local.mealType = dto.mealType
                local.source = dto.source
                local.calories = dto.calories
                local.proteinGrams = dto.proteinGrams
                local.carbsGrams = dto.carbsGrams
                local.fatGrams = dto.fatGrams
                local.notes = dto.notes
                local.analyzedBy = dto.analyzedBy
                local.updatedAt = dto.updatedAt
                // imageData intentionally untouched — a remote pull never
                // carries a photo, and must not erase a local one.
            },
            toDTO: { entry in
                FoodEntryDTO(
                    id: entry.id,
                    name: entry.name,
                    date: entry.date,
                    mealType: entry.mealType,
                    source: entry.source,
                    calories: entry.calories,
                    proteinGrams: entry.proteinGrams,
                    carbsGrams: entry.carbsGrams,
                    fatGrams: entry.fatGrams,
                    notes: entry.notes,
                    analyzedBy: entry.analyzedBy,
                    updatedAt: entry.updatedAt
                )
            }
        )
    }

    private func syncWeightEntries(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "weight_entries",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                WeightEntry(id: dto.id, date: dto.date, weightKg: dto.weightKg, updatedAt: dto.updatedAt)
            },
            applyRemote: { dto, local in
                local.date = dto.date
                local.weightKg = dto.weightKg
                local.updatedAt = dto.updatedAt
            },
            toDTO: { entry in
                WeightEntryDTO(id: entry.id, date: entry.date, weightKg: entry.weightKg, updatedAt: entry.updatedAt)
            }
        )
    }

    // MARK: - Planner

    private func syncPlannerTasks(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "planner_tasks",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<PlannerTask>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                // notificationIdentifier is local-only — see schema.sql's note.
                PlannerTask(
                    id: dto.id,
                    title: dto.title,
                    notes: dto.notes,
                    dueDate: dto.dueDate,
                    reminderDate: dto.reminderDate,
                    isCompleted: dto.isCompleted,
                    priority: TaskPriority(rawValue: dto.priority) ?? .medium,
                    createdAt: dto.createdAt,
                    isFocus: dto.isFocus,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.title = dto.title
                local.notes = dto.notes
                local.dueDate = dto.dueDate
                local.reminderDate = dto.reminderDate
                local.isCompleted = dto.isCompleted
                local.priority = dto.priority
                local.isFocus = dto.isFocus
                local.updatedAt = dto.updatedAt
            },
            toDTO: { task in
                PlannerTaskDTO(
                    id: task.id,
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
                    reminderDate: task.reminderDate,
                    isCompleted: task.isCompleted,
                    priority: task.priority,
                    isFocus: task.isFocus,
                    createdAt: task.createdAt,
                    updatedAt: task.updatedAt
                )
            }
        )
    }

    private func syncPlannerEvents(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "planner_events",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<PlannerEvent>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                PlannerEvent(
                    id: dto.id,
                    title: dto.title,
                    location: dto.location,
                    notes: dto.notes,
                    startDate: dto.startDate,
                    endDate: dto.endDate,
                    isAllDay: dto.isAllDay,
                    hasReminder: dto.hasReminder,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.title = dto.title
                local.location = dto.location
                local.notes = dto.notes
                local.startDate = dto.startDate
                local.endDate = dto.endDate
                local.isAllDay = dto.isAllDay
                local.hasReminder = dto.hasReminder
                local.updatedAt = dto.updatedAt
            },
            toDTO: { event in
                PlannerEventDTO(
                    id: event.id,
                    title: event.title,
                    location: event.location,
                    notes: event.notes,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    hasReminder: event.hasReminder,
                    createdAt: event.createdAt,
                    updatedAt: event.updatedAt
                )
            }
        )
    }

    private func syncPlannerNotes(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "planner_notes",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<PlannerNote>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                PlannerNote(id: dto.id, date: dto.date, text: dto.text, updatedAt: dto.updatedAt)
            },
            applyRemote: { dto, local in
                local.date = dto.date
                local.text = dto.text
                local.updatedAt = dto.updatedAt
            },
            toDTO: { note in
                PlannerNoteDTO(id: note.id, date: note.date, text: note.text, updatedAt: note.updatedAt)
            }
        )
    }

    // MARK: - Finanzas

    private func syncTransactions(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "transactions",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                Transaction(
                    id: dto.id,
                    amount: dto.amount,
                    type: TransactionType(rawValue: dto.type) ?? .expense,
                    category: TransactionCategory(rawValue: dto.category) ?? .other,
                    note: dto.note,
                    date: dto.date,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.amount = dto.amount
                local.type = dto.type
                local.category = dto.category
                local.note = dto.note
                local.date = dto.date
                local.updatedAt = dto.updatedAt
            },
            toDTO: { transaction in
                TransactionDTO(
                    id: transaction.id,
                    amount: transaction.amount,
                    type: transaction.type,
                    category: transaction.category,
                    note: transaction.note,
                    date: transaction.date,
                    updatedAt: transaction.updatedAt
                )
            }
        )
    }

    private func syncCategoryBudgets(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "category_budgets",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                CategoryBudget(id: dto.id, category: TransactionCategory(rawValue: dto.category) ?? .other, monthlyLimit: dto.monthlyLimit, updatedAt: dto.updatedAt)
            },
            applyRemote: { dto, local in
                local.category = dto.category
                local.monthlyLimit = dto.monthlyLimit
                local.updatedAt = dto.updatedAt
            },
            toDTO: { budget in
                CategoryBudgetDTO(id: budget.id, category: budget.category, monthlyLimit: budget.monthlyLimit, updatedAt: budget.updatedAt)
            }
        )
    }

    private func syncRecurringTransactions(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "recurring_transactions",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<RecurringTransaction>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                RecurringTransaction(
                    id: dto.id,
                    name: dto.name,
                    amount: dto.amount,
                    type: TransactionType(rawValue: dto.type) ?? .expense,
                    category: TransactionCategory(rawValue: dto.category) ?? .other,
                    dayOfMonth: dto.dayOfMonth,
                    isActive: dto.isActive,
                    lastAppliedMonth: dto.lastAppliedMonth,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.name = dto.name
                local.amount = dto.amount
                local.type = dto.type
                local.category = dto.category
                local.dayOfMonth = dto.dayOfMonth
                local.isActive = dto.isActive
                local.lastAppliedMonth = dto.lastAppliedMonth
                local.updatedAt = dto.updatedAt
            },
            toDTO: { recurring in
                RecurringTransactionDTO(
                    id: recurring.id,
                    name: recurring.name,
                    amount: recurring.amount,
                    type: recurring.type,
                    category: recurring.category,
                    dayOfMonth: recurring.dayOfMonth,
                    isActive: recurring.isActive,
                    lastAppliedMonth: recurring.lastAppliedMonth,
                    createdAt: recurring.createdAt,
                    updatedAt: recurring.updatedAt
                )
            }
        )
    }

    // MARK: - Medicación

    private func syncMedications(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "medications",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<Medication>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                // notificationIdentifiers is local-only — a medication
                // pulled from the cloud gets its reminders (re)scheduled
                // the next time MedicationRepository touches it, same as
                // any freshly-added one.
                Medication(
                    id: dto.id,
                    name: dto.name,
                    dosage: dto.dosage,
                    notes: dto.notes,
                    reminderMinutesSinceMidnight: dto.reminderMinutesSinceMidnight,
                    isActive: dto.isActive,
                    createdAt: dto.createdAt,
                    updatedAt: dto.updatedAt
                )
            },
            applyRemote: { dto, local in
                local.name = dto.name
                local.dosage = dto.dosage
                local.notes = dto.notes
                local.reminderMinutesSinceMidnight = dto.reminderMinutesSinceMidnight
                local.isActive = dto.isActive
                local.updatedAt = dto.updatedAt
            },
            toDTO: { medication in
                MedicationDTO(
                    id: medication.id,
                    name: medication.name,
                    dosage: medication.dosage,
                    notes: medication.notes,
                    reminderMinutesSinceMidnight: medication.reminderMinutesSinceMidnight,
                    isActive: medication.isActive,
                    createdAt: medication.createdAt,
                    updatedAt: medication.updatedAt
                )
            }
        )
    }

    private func syncMedicationDoseLogs(client: SupabaseClient, context: ModelContext) async {
        await reconcile(
            table: "medication_dose_logs",
            client: client,
            context: context,
            fetchLocal: { (try? context.fetch(FetchDescriptor<MedicationDoseLog>())) ?? [] },
            localID: { $0.id },
            localUpdatedAt: { $0.updatedAt },
            dtoID: { $0.id },
            dtoUpdatedAt: { $0.updatedAt },
            makeLocal: { dto in
                MedicationDoseLog(id: dto.id, medicationID: dto.medicationID, date: dto.date, minuteOfDay: dto.minuteOfDay, takenAt: dto.takenAt, skipped: dto.skipped, updatedAt: dto.updatedAt)
            },
            applyRemote: { dto, local in
                local.medicationID = dto.medicationID
                local.date = dto.date
                local.minuteOfDay = dto.minuteOfDay
                local.takenAt = dto.takenAt
                local.skipped = dto.skipped
                local.updatedAt = dto.updatedAt
            },
            toDTO: { log in
                MedicationDoseLogDTO(id: log.id, medicationID: log.medicationID, date: log.date, minuteOfDay: log.minuteOfDay, takenAt: log.takenAt, skipped: log.skipped, updatedAt: log.updatedAt)
            }
        )
    }

    // MARK: - Singletons (nutrition_goals, budget_settings, user_settings)

    /// Same "gana el más reciente" idea as `reconcile`, but for a table
    /// with exactly one row per user — matched by `user_id` (filtered by
    /// RLS on the way in, targeted by `onConflict: "user_id"` on the way
    /// out), never by `id`. Two devices each create their own local row
    /// with their own random UUID the first time they need one, so `id`
    /// can't be the join key here.
    private func syncSingleton<DTO: Codable & Sendable>(
        table: String,
        client: SupabaseClient,
        dtoUpdatedAt: (DTO) -> Date,
        localUpdatedAt: () -> Date,
        applyRemote: (DTO) -> Void,
        currentDTO: () -> DTO
    ) async {
        if let remote: DTO = await CloudSyncTransport.fetchSingleton(table: table, client: client) {
            if dtoUpdatedAt(remote) > localUpdatedAt() {
                applyRemote(remote)
            }
        }
        await CloudSyncTransport.upsertSingleton(currentDTO(), table: table, client: client)
    }

    private func syncNutritionGoal(client: SupabaseClient, context: ModelContext) async {
        guard let goal = try? context.fetch(FetchDescriptor<NutritionGoal>()).first else { return }
        await syncSingleton(
            table: "nutrition_goals",
            client: client,
            dtoUpdatedAt: { $0.updatedAt },
            localUpdatedAt: { goal.updatedAt },
            applyRemote: { dto in
                goal.dailyCalorieGoal = dto.dailyCalorieGoal
                goal.proteinGoalGrams = dto.proteinGoalGrams
                goal.carbsGoalGrams = dto.carbsGoalGrams
                goal.fatGoalGrams = dto.fatGoalGrams
                goal.targetWeightKg = dto.targetWeightKg
                goal.weeklyRateKg = dto.weeklyRateKg
                goal.updatedAt = dto.updatedAt
            },
            currentDTO: {
                NutritionGoalDTO(
                    dailyCalorieGoal: goal.dailyCalorieGoal,
                    proteinGoalGrams: goal.proteinGoalGrams,
                    carbsGoalGrams: goal.carbsGoalGrams,
                    fatGoalGrams: goal.fatGoalGrams,
                    targetWeightKg: goal.targetWeightKg,
                    weeklyRateKg: goal.weeklyRateKg,
                    updatedAt: goal.updatedAt
                )
            }
        )
        try? context.save()
    }

    private func syncBudgetSettings(client: SupabaseClient, context: ModelContext) async {
        guard let budget = try? context.fetch(FetchDescriptor<BudgetSettings>()).first else { return }
        await syncSingleton(
            table: "budget_settings",
            client: client,
            dtoUpdatedAt: { $0.updatedAt },
            localUpdatedAt: { budget.updatedAt },
            applyRemote: { dto in
                budget.monthlyBudget = dto.monthlyBudget
                budget.totalSavings = dto.totalSavings
                budget.currencyCode = dto.currencyCode
                budget.savingsGoalAmount = dto.savingsGoalAmount
                budget.savingsGoalDate = dto.savingsGoalDate
                budget.updatedAt = dto.updatedAt
            },
            currentDTO: {
                BudgetSettingsDTO(
                    monthlyBudget: budget.monthlyBudget,
                    totalSavings: budget.totalSavings,
                    currencyCode: budget.currencyCode,
                    savingsGoalAmount: budget.savingsGoalAmount,
                    savingsGoalDate: budget.savingsGoalDate,
                    updatedAt: budget.updatedAt
                )
            }
        )
        try? context.save()
    }

    private func syncUserSettings(client: SupabaseClient, context: ModelContext) async {
        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first else { return }
        await syncSingleton(
            table: "user_settings",
            client: client,
            dtoUpdatedAt: { $0.updatedAt },
            localUpdatedAt: { settings.updatedAt },
            applyRemote: { dto in
                settings.preferredAIProvider = dto.preferredAIProvider
                settings.mealReminderNotificationsEnabled = dto.mealReminderNotificationsEnabled
                settings.eventNotificationsEnabled = dto.eventNotificationsEnabled
                settings.displayName = dto.displayName
                settings.email = dto.email
                settings.updatedAt = dto.updatedAt
            },
            currentDTO: {
                UserSettingsDTO(
                    preferredAIProvider: settings.preferredAIProvider,
                    mealReminderNotificationsEnabled: settings.mealReminderNotificationsEnabled,
                    eventNotificationsEnabled: settings.eventNotificationsEnabled,
                    displayName: settings.displayName,
                    email: settings.email,
                    updatedAt: settings.updatedAt
                )
            }
        )
        try? context.save()
    }
}
