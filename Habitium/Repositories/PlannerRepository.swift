//
//  PlannerRepository.swift
//  Habitium
//
//  Data-layer abstraction over PlannerTask/PlannerEvent/PlannerNote
//  persistence, plus a merged "upcoming items" view used by HomeView and
//  the calendar widget.
//

import Foundation
import SwiftData

struct UpcomingPlannerItem: Identifiable, Equatable {
    var id: UUID
    var title: String
    var date: Date
    var isTask: Bool
}

@MainActor
protocol PlannerRepository {
    func tasks(on date: Date?) -> [PlannerTask]
    func addTask(_ task: PlannerTask)
    func toggleComplete(_ task: PlannerTask)
    func deleteTask(_ task: PlannerTask)

    /// Today's "foco del día" tasks (Sunsama-style), incomplete ones first.
    func focusTasks() -> [PlannerTask]
    /// Flips `isFocus`. Turning it on is a no-op (returns false) once 3
    /// tasks are already marked as focus — keeps the list intentionally
    /// short. Turning off always succeeds.
    @discardableResult
    func toggleFocus(_ task: PlannerTask) -> Bool

    func events(on date: Date) -> [PlannerEvent]
    func events(in range: Range<Date>) -> [PlannerEvent]
    func addEvent(_ event: PlannerEvent)
    func deleteEvent(_ event: PlannerEvent)

    func note(for date: Date) -> PlannerNote?
    func saveNote(text: String, for date: Date)

    /// Next `limit` upcoming (incomplete task / future event) items, sorted
    /// by date ascending — feeds HomeView's "next 3" and the calendar widget.
    func upcomingItems(limit: Int) -> [UpcomingPlannerItem]
}

@MainActor
final class SwiftDataPlannerRepository: PlannerRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Tasks

    func tasks(on date: Date?) -> [PlannerTask] {
        var descriptor = FetchDescriptor<PlannerTask>(sortBy: [SortDescriptor(\.dueDate)])
        if let date {
            let range = Calendar.current.dayRange(containing: date)
            descriptor.predicate = #Predicate<PlannerTask> { task in
                if let due = task.dueDate {
                    return due >= range.lowerBound && due < range.upperBound
                }
                return false
            }
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func addTask(_ task: PlannerTask) {
        context.insert(task)
        save()
        syncWidgetSnapshot()
    }

    func toggleComplete(_ task: PlannerTask) {
        task.isCompleted.toggle()
        if task.isCompleted {
            NotificationScheduler.shared.cancelReminder(identifier: task.notificationIdentifier)
        }
        save()
        syncWidgetSnapshot()
    }

    func deleteTask(_ task: PlannerTask) {
        NotificationScheduler.shared.cancelReminder(identifier: task.notificationIdentifier)
        context.delete(task)
        save()
        syncWidgetSnapshot()
    }

    func focusTasks() -> [PlannerTask] {
        let descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate<PlannerTask> { $0.isFocus },
            sortBy: [SortDescriptor(\.isCompleted), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func toggleFocus(_ task: PlannerTask) -> Bool {
        if !task.isFocus && focusTasks().count >= 3 {
            return false
        }
        task.isFocus.toggle()
        save()
        return true
    }

    // MARK: - Events

    func events(on date: Date) -> [PlannerEvent] {
        let range = Calendar.current.dayRange(containing: date)
        return events(in: range)
    }

    func events(in range: Range<Date>) -> [PlannerEvent] {
        let descriptor = FetchDescriptor<PlannerEvent>(
            predicate: #Predicate<PlannerEvent> { event in
                event.startDate >= range.lowerBound && event.startDate < range.upperBound
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func addEvent(_ event: PlannerEvent) {
        context.insert(event)
        save()
        syncWidgetSnapshot()
    }

    func deleteEvent(_ event: PlannerEvent) {
        NotificationScheduler.shared.cancelReminder(identifier: event.notificationIdentifier)
        context.delete(event)
        save()
        syncWidgetSnapshot()
    }

    // MARK: - Notes

    func note(for date: Date) -> PlannerNote? {
        let range = Calendar.current.dayRange(containing: date)
        let descriptor = FetchDescriptor<PlannerNote>(
            predicate: #Predicate<PlannerNote> { note in
                note.date >= range.lowerBound && note.date < range.upperBound
            }
        )
        return (try? context.fetch(descriptor))?.first
    }

    func saveNote(text: String, for date: Date) {
        if let existing = note(for: date) {
            existing.text = text
            existing.updatedAt = .now
        } else {
            context.insert(PlannerNote(date: date, text: text))
        }
        save()
    }

    // MARK: - Upcoming

    func upcomingItems(limit: Int) -> [UpcomingPlannerItem] {
        let now = Date.now
        let incompleteTasks = tasks(on: nil)
            .filter { !$0.isCompleted && ($0.dueDate.map { $0 >= now } ?? false) }
            .compactMap { task -> UpcomingPlannerItem? in
                guard let due = task.dueDate else { return nil }
                return UpcomingPlannerItem(id: task.id, title: task.title, date: due, isTask: true)
            }

        let upcomingEvents = events(in: now..<(Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now))
            .map { UpcomingPlannerItem(id: $0.id, title: $0.title, date: $0.startDate, isTask: false) }

        return (incompleteTasks + upcomingEvents)
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { $0 }
    }

    private func save() {
        try? context.save()
    }

    /// Publishes the next few upcoming items to the shared store so the
    /// calendar widget stays fresh.
    private func syncWidgetSnapshot() {
        let items = upcomingItems(limit: 5).map {
            CalendarWidgetSnapshot.UpcomingItem(id: $0.id, title: $0.title, date: $0.date, isTask: $0.isTask)
        }
        SharedDataStore.writeCalendarSnapshot(CalendarWidgetSnapshot(items: items, updatedAt: .now))
        WidgetRefresher.reloadCalendarWidget()
        WatchConnectivityBridge.shared.sendCurrentSnapshots()
    }
}
