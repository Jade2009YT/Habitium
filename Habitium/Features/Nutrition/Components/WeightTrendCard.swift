//
//  WeightTrendCard.swift
//  Habitium
//
//  Compact weight trend line + a quick "log weight" action — the same
//  building block PlateLens and Lose It! lean on to make calorie goals
//  feel adaptive instead of static.
//

import Charts
import SwiftUI

struct WeightTrendCard: View {
    let entries: [WeightEntry] // newest first
    var onLogWeight: (Double) -> Void

    @State private var showingLogSheet = false
    @State private var weightText = ""

    private var chronological: [WeightEntry] { entries.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Peso corporal", systemImage: "figure.stand")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingLogSheet = true
                } label: {
                    Label("Registrar", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                }
            }

            if let latest = entries.first {
                Text(latest.weightKg, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                +
                Text(" kg").font(.subheadline).foregroundStyle(.secondary)

                if chronological.count > 1 {
                    Chart(chronological) { entry in
                        LineMark(x: .value("Fecha", entry.date), y: .value("Peso", entry.weightKg))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Theme.Colors.nutrition)
                        PointMark(x: .value("Fecha", entry.date), y: .value("Peso", entry.weightKg))
                            .foregroundStyle(Theme.Colors.nutrition)
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: 60)
                } else {
                    Text("Registra un par de pesajes más para ver la tendencia.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Sin registros todavía.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .sheet(isPresented: $showingLogSheet) {
            NavigationStack {
                Form {
                    TextField("Peso (kg)", text: $weightText)
                        .keyboardType(.decimalPad)
                }
                .navigationTitle("Registrar peso")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showingLogSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") {
                            if let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
                                onLogWeight(value)
                            }
                            weightText = ""
                            showingLogSheet = false
                        }
                        .disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
                    }
                }
            }
            .presentationDetents([.height(180)])
        }
    }
}

#Preview {
    WeightTrendCard(entries: [
        WeightEntry(date: .now, weightKg: 74.2),
        WeightEntry(date: .now.addingTimeInterval(-86400 * 3), weightKg: 74.8),
        WeightEntry(date: .now.addingTimeInterval(-86400 * 7), weightKg: 75.5)
    ]) { _ in }
    .padding()
}
