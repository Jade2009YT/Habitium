//
//  PlannerEvent.swift
//  Habitium
//
//  SwiftData model for a calendar event (as opposed to an open-ended
//  to-do). Shown in the monthly/daily calendar and can trigger a local
//  notification.
//

import Foundation
import SwiftData

@Model
final class PlannerEvent {
    var id: UUID
    var title: String
    var location: String?
    var notes: String?
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var hasReminder: Bool
    var notificationIdentifier: String?
    var createdAt: Date
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        location: String? = nil,
        notes: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        hasReminder: Bool = true,
        notificationIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(3600)
        self.isAllDay = isAllDay
        self.hasReminder = hasReminder
        self.notificationIdentifier = notificationIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
