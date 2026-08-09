//
//  CalorieProgressView.swift
//  Habitium
//
//  Visual summary card: calories consumed vs. goal, plus a macro
//  breakdown, reused by FoodTrackerView (and mirrored in the widget).
//

import SwiftUI

struct CalorieProgressView: View {
    let progress: NutritionDailyProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(progress.consumedCalories))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("/ \(Int(progress.goalCalories)) kcal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                if progress.isOverGoal {
                    Label("Meta superada", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.danger)
                }
            }

            ProgressView(value: progress.progress)
                .tint(progress.isOverGoal ? Theme.Colors.danger : Theme.Colors.nutrition)

            HStack(spacing: 16) {
                macroPill(title: "Proteína", value: progress.consumedMacros.proteinGrams, goal: progress.goalMacros.proteinGrams)
                macroPill(title: "Carbos", value: progress.consumedMacros.carbsGrams, goal: progress.goalMacros.carbsGrams)
                macroPill(title: "Grasas", value: progress.consumedMacros.fatGrams, goal: progress.goalMacros.fatGrams)
            }
        }
        .cardStyle()
    }

    private func macroPill(title: String, value: Double, goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(value))g / \(Int(goal))g").font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    CalorieProgressView(progress: .init(
        consumedCalories: 1450, goalCalories: 2000,
        consumedMacros: .init(proteinGrams: 80, carbsGrams: 140, fatGrams: 40),
        goalMacros: .init(proteinGrams: 120, carbsGrams: 225, fatGrams: 65)
    ))
    .padding()
}
