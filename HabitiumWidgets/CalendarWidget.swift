//
//  CalendarWidget.swift
//  HabitiumWidgets
//
//  Home screen and Lock Screen widget: the next task or event, with an
//  interactive "complete" button (CompleteTaskIntent) that marks a task
//  done directly from the widget without opening the app.
//

import SwiftUI
import WidgetKit

struct CalendarTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(CalendarEntry(date: .now, snapshot: SharedDataStore.readCalendarSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let entry = CalendarEntry(date: .now, snapshot: SharedDataStore.readCalendarSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct CalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
}

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarEntry

    private var nextItem: CalendarWidgetSnapshot.UpcomingItem? {
        entry.snapshot.items.first
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack {
                Image(systemName: "calendar")
                if let nextItem {
                    Text(nextItem.date, style: .time).font(.caption2)
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(nextItem?.title ?? "Sin pendientes", systemImage: "calendar")
                    .font(.headline)
                    .lineLimit(1)
                if let nextItem {
                    Text(nextItem.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                }
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Calendario", systemImage: "calendar")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Spacer()
                if let nextItem {
                    Text(nextItem.title).font(.subheadline.bold()).lineLimit(2)
                    Text(nextItem.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sin pendientes").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()

        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Próximo en tu calendario", systemImage: "calendar")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                if entry.snapshot.items.isEmpty {
                    Text("Sin tareas ni eventos próximos").foregroundStyle(.secondary)
                } else {
                    ForEach(entry.snapshot.items.prefix(2)) { item in
                        HStack {
                            Image(systemName: item.isTask ? "checklist" : "calendar.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(item.title).font(.subheadline.bold()).lineLimit(1)
                                Text(item.date.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.isTask {
                                Button(intent: CompleteTaskIntent(taskID: item.id.uuidString)) {
                                    Image(systemName: "checkmark.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.calendar, provider: CalendarTimelineProvider()) { entry in
            CalendarWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calendario")
        .description("Próxima tarea o evento del día.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    CalendarWidget()
} timeline: {
    CalendarEntry(date: .now, snapshot: .placeholder)
}
