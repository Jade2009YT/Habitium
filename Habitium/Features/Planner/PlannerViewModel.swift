//
//  PlannerViewModel.swift
//  Habitium
//
//  Drives PlannerView: the selected day's tasks/events/note, and which
//  days in the visible month have items (for the calendar grid dots).
//

import Foundation
import Observation

@MainActor
@Observable
final class PlannerViewModel {

    var selectedDate: Date = .now {
        didSet { loadDay() }
    }
    var visibleMonth: Date = .now {
        didSet { loadMonthMarkers() }
    }

    private(set) var tasksForDay: [PlannerTask] = []
    private(set) var eventsForDay: [PlannerEvent] = []
    private(set) var noteText: String = ""
    /// Start-of-day dates within the visible month that have at least one
    /// task or event, used to draw a dot under those days.
    private(set) var daysWithItems: Set<Date> = []

    private let container: AppDependencyContainer
    private var repository: PlannerRepository { container.plannerRepository }

    init(container: AppDependencyContainer) {
        self.container = container
        loadDay()
        loadMonthMarkers()
    }

    func loadDay() {
        tasksForDay = repository.tasks(on: selectedDate)
        eventsForDay = repository.events(on: selectedDate)
        noteText = repository.note(for: selectedDate)?.text ?? ""
    }

    func loadMonthMarkers() {
        let calendar = Calendar.current
        let monthRange = calendar.monthRange(containing: visibleMonth)
        let tasks = repository.tasks(on: nil).filter {
            guard let due = $0.dueDate else { return false }
            return due >= monthRange.lowerBound && due < monthRange.upperBound
        }
        let events = repository.events(in: monthRange)

        var days = Set<Date>()
        for task in tasks {
            if let due = task.dueDate { days.insert(calendar.startOfDay(for: due)) }
        }
        for event in events {
            days.insert(calendar.startOfDay(for: event.startDate))
        }
        daysWithItems = days
    }

    func addTask(title: String, dueDate: Date, reminderDate: Date?, priority: TaskPriority) {
        var identifier: String?
        if let reminderDate {
            identifier = NotificationScheduler.shared.scheduleReminder(title: "Tarea: \(title)", body: "Vence hoy", at: reminderDate)
        }
        let task = PlannerTask(title: title, dueDate: dueDate, reminderDate: reminderDate, priority: priority, notificationIdentifier: identifier)
        repository.addTask(task)
        refreshAll()
    }

    func toggleTask(_ task: PlannerTask) {
        repository.toggleComplete(task)
        refreshAll()
    }

    func deleteTask(_ task: PlannerTask) {
        repository.deleteTask(task)
        refreshAll()
    }

    /// Returns false when the task couldn't be marked as focus because
    /// today's foco del día already has 3 tasks — the view can show a
    /// hint in that case.
    @discardableResult
    func toggleFocus(_ task: PlannerTask) -> Bool {
        let succeeded = repository.toggleFocus(task)
        if succeeded { refreshAll() }
        return succeeded
    }

    /// Fantastical-style natural-language quick add: "Gimnasio mañana
    /// 18:00" becomes an event titled "Gimnasio" starting tomorrow at 6pm.
    func addQuickEvent(from text: String) {
        let parsed = NaturalLanguageQuickAdd.parse(text, defaultDate: selectedDate)
        addEvent(title: parsed.title, startDate: parsed.date, endDate: parsed.date.addingTimeInterval(3600), location: nil, reminder: true)
    }

    func addEvent(title: String, startDate: Date, endDate: Date, location: String?, reminder: Bool) {
        var identifier: String?
        if reminder {
            identifier = NotificationScheduler.shared.scheduleReminder(title: title, body: location ?? "Evento próximo", at: startDate.addingTimeInterval(-15 * 60))
        }
        let event = PlannerEvent(title: title, location: location, startDate: startDate, endDate: endDate, hasReminder: reminder, notificationIdentifier: identifier)
        repository.addEvent(event)
        refreshAll()
    }

    func deleteEvent(_ event: PlannerEvent) {
        repository.deleteEvent(event)
        refreshAll()
    }

    func saveNote() {
        repository.saveNote(text: noteText, for: selectedDate)
    }

    private func refreshAll() {
        loadDay()
        loadMonthMarkers()
    }
}
