//
//  NutritionWidget.swift
//  HabitiumWidgets
//
//  Home screen (small/medium) and Lock Screen widget: today's calorie
//  progress, with an interactive button that opens Habitium straight into
//  the "add meal" flow (OpenScanFoodIntent, defined in Shared/Intents).
//

import SwiftUI
import WidgetKit

struct NutritionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry {
        NutritionEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        completion(NutritionEntry(date: .now, snapshot: SharedDataStore.readNutritionSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let entry = NutritionEntry(date: .now, snapshot: SharedDataStore.readNutritionSnapshot())
        // Nutrition data changes whenever the app logs a meal (which also
        // triggers an immediate reload), so a slow fallback refresh is
        // enough to keep things correct if a reload was ever missed.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct NutritionEntry: TimelineEntry {
    let date: Date
    let snapshot: NutritionWidgetSnapshot
}

struct NutritionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NutritionEntry

    private var progress: Double {
        entry.snapshot.goalCalories > 0 ? min(entry.snapshot.consumedCalories / entry.snapshot.goalCalories, 1.0) : 0
    }
    private var remaining: Int {
        max(0, Int(entry.snapshot.goalCalories - entry.snapshot.consumedCalories))
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "flame.fill")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.green)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(remaining) kcal restantes", systemImage: "flame.fill")
                    .font(.headline)
                ProgressView(value: progress)
            }

        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Label("Nutrición", systemImage: "flame.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                Spacer()
                Text("\(remaining)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("kcal restantes")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress).tint(.green)
                Button(intent: OpenScanFoodIntent()) {
                    Label("Escanear", systemImage: "camera.fill")
                        .font(.caption2.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()

        default: // .systemMedium and any other family
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Nutrición", systemImage: "flame.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    Text("\(remaining) kcal restantes")
                        .font(.title2.bold())
                    ProgressView(value: progress).tint(.green)
                    Text("\(Int(entry.snapshot.consumedCalories)) / \(Int(entry.snapshot.goalCalories)) kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(intent: OpenScanFoodIntent()) {
                    VStack {
                        Image(systemName: "camera.fill")
                        Text("Escanear").font(.caption2)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
    }
}

struct NutritionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nutrition, provider: NutritionTimelineProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nutrición")
        .description("Progreso diario de calorías y acceso rápido para escanear comida.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    NutritionWidget()
} timeline: {
    NutritionEntry(date: .now, snapshot: .placeholder)
}
