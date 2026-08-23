//
//  MedicationWidget.swift
//  HabitiumWidgets
//
//  Home screen and Lock Screen widget: the next pending medication dose,
//  with an interactive "tomada" button (MarkDoseTakenIntent) that marks
//  it done directly from the widget without opening the app.
//

import SwiftUI
import WidgetKit

struct MedicationTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedicationEntry {
        MedicationEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MedicationEntry) -> Void) {
        completion(MedicationEntry(date: .now, snapshot: SharedDataStore.readMedicationSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MedicationEntry>) -> Void) {
        let entry = MedicationEntry(date: .now, snapshot: SharedDataStore.readMedicationSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct MedicationEntry: TimelineEntry {
    let date: Date
    let snapshot: MedicationWidgetSnapshot
}

struct MedicationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MedicationEntry

    private var hasNextDose: Bool { entry.snapshot.nextDoseName != nil }

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack {
                Image(systemName: "pills.fill")
                if entry.snapshot.pendingCount > 0 {
                    Text("\(entry.snapshot.pendingCount)").font(.caption2.bold())
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.snapshot.nextDoseName ?? "Sin tomas pendientes", systemImage: "pills.fill")
                    .font(.headline)
                    .lineLimit(1)
                if let time = entry.snapshot.nextDoseTime {
                    Text(time.formatted(date: .omitted, time: .shortened)).font(.caption2)
                }
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Medicación", systemImage: "pills.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
                Spacer()
                if hasNextDose {
                    Text(entry.snapshot.nextDoseName ?? "").font(.subheadline.bold()).lineLimit(2)
                    if let time = entry.snapshot.nextDoseTime {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Sin tomas pendientes").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()

        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Próxima medicación", systemImage: "pills.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)

                if hasNextDose {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.snapshot.nextDoseName ?? "").font(.subheadline.bold()).lineLimit(1)
                            HStack(spacing: 4) {
                                if let dosage = entry.snapshot.nextDoseDosage {
                                    Text(dosage).font(.caption2).foregroundStyle(.secondary)
                                }
                                if let time = entry.snapshot.nextDoseTime {
                                    Text(time.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if let id = entry.snapshot.nextDoseIdentifier {
                            Button(intent: MarkDoseTakenIntent(medicationID: id.medicationID, minuteOfDay: id.minuteOfDay)) {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if entry.snapshot.pendingCount > 1 {
                        Text("+\(entry.snapshot.pendingCount - 1) más hoy")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Sin tomas pendientes").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

struct MedicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.medication, provider: MedicationTimelineProvider()) { entry in
            MedicationWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Medicación")
        .description("Tu próxima toma de medicación.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    MedicationWidget()
} timeline: {
    MedicationEntry(date: .now, snapshot: .placeholder)
}
