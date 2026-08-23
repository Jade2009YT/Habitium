//
//  Medication.swift
//  Habitium
//
//  A medication the user takes on a recurring daily schedule (one or more
//  times a day). Reminder times are stored as minutes-since-midnight
//  (e.g. 480 = 08:00) rather than full Dates, since what matters is the
//  time of day, repeated every day — SwiftData doesn't need a native
//  array-of-DateComponents type for that.
//

import Foundation
import SwiftData

@Model
final class Medication {
    var id: UUID
    var name: String
    var dosage: String?
    var notes: String?
    /// Minutes since midnight for each scheduled dose, e.g. [480, 1200]
    /// for 08:00 and 20:00.
    var reminderMinutesSinceMidnight: [Int]
    var isActive: Bool
    /// One UNNotificationRequest identifier per entry in
    /// reminderMinutesSinceMidnight, in the same order — lets the
    /// repository cancel/reschedule them precisely when edited.
    var notificationIdentifiers: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String? = nil,
        notes: String? = nil,
        reminderMinutesSinceMidnight: [Int] = [],
        isActive: Bool = true,
        notificationIdentifiers: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.notes = notes
        self.reminderMinutesSinceMidnight = reminderMinutesSinceMidnight.sorted()
        self.isActive = isActive
        self.notificationIdentifiers = notificationIdentifiers
        self.createdAt = createdAt
    }
}

/// One logged outcome (taken/skipped) for a specific medication, day, and
/// scheduled time slot — the tuple (medicationID, date, minuteOfDay)
/// identifies a unique dose.
@Model
final class MedicationDoseLog {
    var id: UUID
    var medicationID: UUID
    /// Start-of-day date this dose belongs to.
    var date: Date
    var minuteOfDay: Int
    var takenAt: Date?
    var skipped: Bool

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        date: Date,
        minuteOfDay: Int,
        takenAt: Date? = nil,
        skipped: Bool = false
    ) {
        self.id = id
        self.medicationID = medicationID
        self.date = date
        self.minuteOfDay = minuteOfDay
        self.takenAt = takenAt
        self.skipped = skipped
    }
}
