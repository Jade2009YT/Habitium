//
//  NotificationScheduler.swift
//  Habitium
//
//  Thin wrapper around UNUserNotificationCenter for local notifications:
//  planner task/event reminders and meal-logging nudges. No push/remote
//  notifications are used — everything is scheduled on-device.
//

import Foundation
import UserNotifications

final class NotificationScheduler {

    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Schedules a reminder and returns the identifier to persist on the
    /// owning model (PlannerTask/PlannerEvent) so it can be cancelled later.
    @discardableResult
    func scheduleReminder(title: String, body: String, at date: Date) -> String? {
        guard date > .now else { return nil }

        let identifier = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
        return identifier
    }

    func cancelReminder(identifier: String?) {
        guard let identifier else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Convenience for the daily "log your meal" nudge, e.g. scheduled once
    /// at a fixed hour, repeating daily.
    func scheduleDailyMealReminder(hour: Int, minute: Int) {
        let identifier = "daily-meal-reminder"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Registra tu comida"
        content.body = "No olvides registrar lo que has comido hoy en Habitium."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelDailyMealReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-meal-reminder"])
    }

    /// Schedules one daily-repeating reminder per entry in
    /// `minutesSinceMidnight` for a medication, returning the identifiers
    /// in the same order so the caller can persist them on the Medication
    /// model and cancel them precisely later (e.g. if the schedule
    /// changes or the medication is deleted).
    func scheduleMedicationReminders(medicationName: String, dosage: String?, minutesSinceMidnight: [Int]) -> [String] {
        minutesSinceMidnight.map { minute in
            let identifier = "medication-\(UUID().uuidString)"
            let content = UNMutableNotificationContent()
            content.title = "Toma tu medicación"
            content.body = dosage.map { "\(medicationName) — \($0)" } ?? medicationName
            content.sound = .default

            var components = DateComponents()
            components.hour = minute / 60
            components.minute = minute % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
            return identifier
        }
    }

    func cancelReminders(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
