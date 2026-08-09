//
//  FinanceWidget.swift
//  HabitiumWidgets
//
//  Home screen and Lock Screen widget: available balance to spend this
//  month, with an interactive button to log a new expense.
//

import SwiftUI
import WidgetKit

struct FinanceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinanceEntry {
        FinanceEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FinanceEntry) -> Void) {
        completion(FinanceEntry(date: .now, snapshot: SharedDataStore.readFinanceSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceEntry>) -> Void) {
        let entry = FinanceEntry(date: .now, snapshot: SharedDataStore.readFinanceSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct FinanceEntry: TimelineEntry {
    let date: Date
    let snapshot: FinanceWidgetSnapshot
}

struct FinanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinanceEntry

    private var currencyFormat: FloatingPointFormatStyle<Double>.Currency {
        .currency(code: entry.snapshot.currencyCode)
    }
    private var progress: Double {
        entry.snapshot.monthlyBudget > 0
            ? min((entry.snapshot.monthlyBudget - entry.snapshot.availableToSpend) / entry.snapshot.monthlyBudget, 1.0)
            : 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "banknote.fill")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.orange)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.snapshot.availableToSpend.formatted(currencyFormat), systemImage: "banknote.fill")
                    .font(.headline)
                Text("Disponible este mes").font(.caption2)
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Finanzas", systemImage: "banknote.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Text(entry.snapshot.availableToSpend, format: currencyFormat)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("disponible este mes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress).tint(.orange)
            }
            .padding()

        default:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Finanzas", systemImage: "banknote.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(entry.snapshot.availableToSpend, format: currencyFormat)
                        .font(.title2.bold())
                    Text("disponible de \(entry.snapshot.monthlyBudget.formatted(currencyFormat))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress).tint(.orange)
                }
                Spacer()
                Button(intent: OpenAddExpenseIntent()) {
                    VStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Añadir").font(.caption2)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
        }
    }
}

struct FinanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.finance, provider: FinanceTimelineProvider()) { entry in
            FinanceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Finanzas")
        .description("Saldo disponible para gastar este mes.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    FinanceWidget()
} timeline: {
    FinanceEntry(date: .now, snapshot: .placeholder)
}
