//
//  WatchSummaryView.swift
//  HabitiumWatch
//
//  The whole v1 Watch app: a single glanceable screen mirroring the four
//  HomeView cards on iPhone, fed by whatever WatchConnectivityBridge last
//  synced. No interactions beyond looking — see README for what a
//  read-write v2 (mark a dose taken from the wrist) would need.
//

import SwiftUI

struct WatchSummaryView: View {
    @Environment(WatchConnectivityBridge.self) private var bridge

    var body: some View {
        NavigationStack {
            ScrollView {
                if let payload = bridge.latestPayload {
                    VStack(alignment: .leading, spacing: 12) {
                        nutritionCard(payload.nutrition)
                        medicationCard(payload.medication)
                        calendarCard(payload.calendar)
                        financeCard(payload.finance)

                        Text("Actualizado \(payload.nutrition.updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Abre Habitium en tu iPhone para sincronizar.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle("Habitium")
        }
    }

    private func nutritionCard(_ snapshot: NutritionWidgetSnapshot) -> some View {
        let remaining = max(0, snapshot.goalCalories - snapshot.consumedCalories)
        return VStack(alignment: .leading, spacing: 2) {
            Label("Calorías", systemImage: "flame.fill").font(.caption2.bold()).foregroundStyle(.green)
            Text("\(Int(remaining)) kcal restantes").font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func medicationCard(_ snapshot: MedicationWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Medicación", systemImage: "pills.fill").font(.caption2.bold()).foregroundStyle(.purple)
            if let name = snapshot.nextDoseName, let time = snapshot.nextDoseTime {
                Text("\(name) · \(time.formatted(date: .omitted, time: .shortened))").font(.subheadline.bold())
            } else {
                Text("Sin tomas pendientes").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func calendarCard(_ snapshot: CalendarWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Próximo", systemImage: "calendar").font(.caption2.bold()).foregroundStyle(.blue)
            if let item = snapshot.items.first {
                Text("\(item.title) · \(item.date.formatted(date: .omitted, time: .shortened))").font(.subheadline.bold())
            } else {
                Text("Nada pendiente").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    private func financeCard(_ snapshot: FinanceWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Disponible", systemImage: "banknote.fill").font(.caption2.bold()).foregroundStyle(.orange)
            Text(snapshot.availableToSpend.formatted(.currency(code: snapshot.currencyCode))).font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    WatchSummaryView()
        .environment(WatchConnectivityBridge.shared)
}
