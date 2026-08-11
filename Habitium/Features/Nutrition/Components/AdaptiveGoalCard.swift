//
//  AdaptiveGoalCard.swift
//  Habitium
//
//  Surfaces the adaptive calorie-goal suggestion (see
//  CalculateAdaptiveCalorieGoalUseCase) with a one-tap way to apply it —
//  or ignore it. Only appears when there's an actionable suggestion.
//

import SwiftUI

struct AdaptiveGoalCard: View {
    let suggestion: AdaptiveCalorieGoalSuggestion
    var onApply: () -> Void

    private var isIncrease: Bool { suggestion.difference > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Habitium sugiere ajustar tu meta", systemImage: "wand.and.stars")
                .font(.caption.bold())
                .foregroundStyle(Theme.Colors.nutrition)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(suggestion.currentCalories))").strikethrough().foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                Text("\(Int(suggestion.suggestedCalories)) kcal").font(.title3.bold())
            }

            Text("Según tu tendencia real de las últimas \(suggestion.windowDays) días (mantenimiento estimado ≈ \(Int(suggestion.estimatedMaintenanceCalories)) kcal, \(rateDescription)).")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button(action: onApply) {
                Label(isIncrease ? "Aumentar meta" : "Reducir meta", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.nutrition)
        }
        .cardStyle()
    }

    private var rateDescription: String {
        let rate = suggestion.observedWeeklyRateKg
        let formatted = abs(rate).formatted(.number.precision(.fractionLength(1)))
        if rate < -0.05 { return "perdiendo ≈\(formatted) kg/semana" }
        if rate > 0.05 { return "ganando ≈\(formatted) kg/semana" }
        return "peso estable"
    }
}

#Preview {
    AdaptiveGoalCard(suggestion: .init(
        suggestedCalories: 2150, currentCalories: 2000, estimatedMaintenanceCalories: 2400,
        observedWeeklyRateKg: -0.3, windowDays: 21
    )) {}
    .padding()
}
