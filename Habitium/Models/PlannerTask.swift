//
//  PlannerTask.swift
//  Habitium
//
//  SwiftData model for a to-do item shown in PlannerView and, when
//  incomplete and due soon, surfaced on HomeView / the calendar widget.
//

import Foundation
import SwiftData

enum TaskPriority: String, Codable, CaseIterable, Comparable {
    case low, medium, high

    private var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var displayName: String {
        switch self {
        case .low: return "Baja"
        case .medium: return "Media"
        case .high: return "Alta"
        }
    }
}

@Model
final class PlannerTask {
    var id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var reminderDate: Date?
    var isCompleted: Bool
    var priority: TaskPriority.RawValue
    var createdAt: Date

    /// Identifier of the scheduled UNNotificationRequest, so it can be
    /// cancelled/updated if the task changes or completes.
    var notificationIdentifier: String?

    /// Marks this task as one of today's "foco del día" — Sunsama-style
    /// intentional daily planning. The repository caps this at 3 tasks at
    /// a time (see PlannerRepository.toggleFocus).
    var isFocus: Bool
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        createdAt: Date = .now,
        notificationIdentifier: String? = nil,
        isFocus: Bool = false,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.isCompleted = isCompleted
        self.priority = priority.rawValue
        self.createdAt = createdAt
        self.notificationIdentifier = notificationIdentifier
        self.isFocus = isFocus
        self.updatedAt = updatedAt
    }
}
