//
//  CloudSyncDTOs.swift
//  Habitium
//
//  Wire-format structs for CloudSyncService — one per Supabase table (see
//  supabase/schema.sql). Deliberately separate from the @Model classes:
//  SwiftData models carry raw enum rawValues as their storage type
//  already (matches Postgres text columns fine), but keeping a dedicated
//  Codable type here means a schema/model change can't silently break
//  the wire format without the compiler complaining at this file.
//
//  Every column name uses snake_case (CodingKeys) to match Postgres.
//  `user_id` is never part of these types on purpose — it's populated
//  server-side from `auth.uid()` on INSERT/UPDATE (see the columns'
//  `default auth.uid()` in schema.sql) and filtered automatically by RLS
//  on SELECT, so the client never needs to read or write it.
//
//  ⚠️ Same disclaimer as SupabaseAuthManager: written from training
//  knowledge of supabase-swift v2's PostgrestClient, without a compiler
//  to check it against. Dates are assumed to round-trip as ISO 8601
//  (matches Postgres `timestamptz`) via the client's default
//  encoder/decoder — if Xcode complains about date decoding, the fix is
//  almost certainly configuring `PostgrestClient`'s encoder/decoder with
//  an explicit `.iso8601` date strategy where `SupabaseClient` is
//  constructed (SupabaseAuthManager.init), not a change to these types.
//

import Foundation

// MARK: - Hábitos

struct HabitDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var symbolName: String
    var kind: String
    var targetValue: Double?
    var goalDirection: String
    var unit: String?
    var isActive: Bool
    var sortOrder: Int
    var linkedToWorkouts: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, kind, unit
        case symbolName = "symbol_name"
        case targetValue = "target_value"
        case goalDirection = "goal_direction"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case linkedToWorkouts = "linked_to_workouts"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct HabitLogDTO: Codable, Sendable {
    var id: UUID
    var habitID: UUID
    var date: Date
    var isCompleted: Bool
    var value: Double?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date, value
        case habitID = "habit_id"
        case isCompleted = "is_completed"
        case updatedAt = "updated_at"
    }
}

// MARK: - Entrenamientos

struct WorkoutSetDTO: Codable, Sendable {
    var id: UUID
    var exerciseName: String
    var reps: Int
    var date: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reps, date
        case exerciseName = "exercise_name"
        case updatedAt = "updated_at"
    }
}

// MARK: - Nutrición

struct FoodEntryDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var date: Date
    var mealType: String
    var source: String
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var notes: String?
    var analyzedBy: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, date, calories, notes
        case mealType = "meal_type"
        case source
        case proteinGrams = "protein_grams"
        case carbsGrams = "carbs_grams"
        case fatGrams = "fat_grams"
        case analyzedBy = "analyzed_by"
        case updatedAt = "updated_at"
    }
}

struct WeightEntryDTO: Codable, Sendable {
    var id: UUID
    var date: Date
    var weightKg: Double
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date
        case weightKg = "weight_kg"
        case updatedAt = "updated_at"
    }
}

/// Singleton (one row per user, matched by `user_id`, not `id`) — see
/// CloudSyncService.syncSingleton. No `id` field: push omits it entirely
/// so `upsert(onConflict: "user_id")` never touches the primary key.
struct NutritionGoalDTO: Codable, Sendable {
    var dailyCalorieGoal: Double
    var proteinGoalGrams: Double
    var carbsGoalGrams: Double
    var fatGoalGrams: Double
    var targetWeightKg: Double?
    var weeklyRateKg: Double?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case dailyCalorieGoal = "daily_calorie_goal"
        case proteinGoalGrams = "protein_goal_grams"
        case carbsGoalGrams = "carbs_goal_grams"
        case fatGoalGrams = "fat_goal_grams"
        case targetWeightKg = "target_weight_kg"
        case weeklyRateKg = "weekly_rate_kg"
        case updatedAt = "updated_at"
    }
}

// MARK: - Planner

struct PlannerTaskDTO: Codable, Sendable {
    var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var reminderDate: Date?
    var isCompleted: Bool
    var priority: String
    var isFocus: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, notes, priority
        case dueDate = "due_date"
        case reminderDate = "reminder_date"
        case isCompleted = "is_completed"
        case isFocus = "is_focus"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlannerEventDTO: Codable, Sendable {
    var id: UUID
    var title: String
    var location: String?
    var notes: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var hasReminder: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, location, notes
        case startDate = "start_date"
        case endDate = "end_date"
        case isAllDay = "is_all_day"
        case hasReminder = "has_reminder"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PlannerNoteDTO: Codable, Sendable {
    var id: UUID
    var date: Date
    var text: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date, text
        case updatedAt = "updated_at"
    }
}

// MARK: - Finanzas

struct TransactionDTO: Codable, Sendable {
    var id: UUID
    var amount: Double
    var type: String
    var category: String
    var note: String?
    var date: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, amount, type, category, note, date
        case updatedAt = "updated_at"
    }
}

/// Singleton — see NutritionGoalDTO's comment.
struct BudgetSettingsDTO: Codable, Sendable {
    var monthlyBudget: Double
    var totalSavings: Double
    var currencyCode: String
    var savingsGoalAmount: Double?
    var savingsGoalDate: Date?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case monthlyBudget = "monthly_budget"
        case totalSavings = "total_savings"
        case currencyCode = "currency_code"
        case savingsGoalAmount = "savings_goal_amount"
        case savingsGoalDate = "savings_goal_date"
        case updatedAt = "updated_at"
    }
}

struct CategoryBudgetDTO: Codable, Sendable {
    var id: UUID
    var category: String
    var monthlyLimit: Double
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, category
        case monthlyLimit = "monthly_limit"
        case updatedAt = "updated_at"
    }
}

struct RecurringTransactionDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var amount: Double
    var type: String
    var category: String
    var dayOfMonth: Int
    var isActive: Bool
    var lastAppliedMonth: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, amount, type, category
        case dayOfMonth = "day_of_month"
        case isActive = "is_active"
        case lastAppliedMonth = "last_applied_month"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Medicación

struct MedicationDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var dosage: String?
    var notes: String?
    var reminderMinutesSinceMidnight: [Int]
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, notes
        case reminderMinutesSinceMidnight = "reminder_minutes_since_midnight"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MedicationDoseLogDTO: Codable, Sendable {
    var id: UUID
    var medicationID: UUID
    var date: Date
    var minuteOfDay: Int
    var takenAt: Date?
    var skipped: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date, skipped
        case medicationID = "medication_id"
        case minuteOfDay = "minute_of_day"
        case takenAt = "taken_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Preferencias (singleton)

struct UserSettingsDTO: Codable, Sendable {
    var preferredAIProvider: String
    var mealReminderNotificationsEnabled: Bool
    var eventNotificationsEnabled: Bool
    var displayName: String?
    var email: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case preferredAIProvider = "preferred_ai_provider"
        case mealReminderNotificationsEnabled = "meal_reminder_notifications_enabled"
        case eventNotificationsEnabled = "event_notifications_enabled"
        case displayName = "display_name"
        case email
        case updatedAt = "updated_at"
    }
}
