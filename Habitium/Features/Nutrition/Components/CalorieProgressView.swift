//
//  CalorieProgressView.swift
//  Habitium
//
//  La tarjeta principal de Nutrición: el anillo de calorías, lo que
//  queda, y los tres macros con su barra.
//
//  Por qué el anillo y no una barra: es la cifra que se mira de un
//  vistazo veinte veces al día, y un anillo se lee sin tener que
//  comparar longitudes. La barra se reserva para los macros, donde lo
//  interesante SÍ es comparar tres cosas entre sí.
//
//  Usa `rawProgress` (sin limitar) y no `progress`: el limitado nunca
//  pasa de 1, así que el estado "te has pasado" —anillo y barras en
//  rojo— no llegaría a dispararse nunca.
//

import SwiftUI

struct CalorieProgressView: View {
    let progress: NutritionDailyProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "Hoy", symbol: "flame.fill", color: Theme.Colors.nutrition) {
                if progress.isOverGoal {
                    Label("Te has pasado", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.danger)
                }
            }

            HStack(spacing: 20) {
                ZStack {
                    RingProgress(
                        progress: progress.rawProgress,
                        color: Theme.Colors.nutrition,
                        lineWidth: 13,
                        size: 132
                    )
                    VStack(spacing: 0) {
                        CountingInt(
                            value: Int(progress.remainingCalories),
                            color: progress.isOverGoal ? Theme.Colors.danger : .primary
                        )
                        Text("kcal restantes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    macroRow("Proteína", progress.consumedMacros.proteinGrams, progress.goalMacros.proteinGrams)
                    macroRow("Carbos", progress.consumedMacros.carbsGrams, progress.goalMacros.carbsGrams)
                    macroRow("Grasas", progress.consumedMacros.fatGrams, progress.goalMacros.fatGrams)
                }
            }

            Text("\(Int(progress.consumedCalories)) de \(Int(progress.goalCalories)) kcal consumidas")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func macroRow(_ title: String, _ value: Double, _ goal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(Int(value))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                if goal > 0 {
                    Text("/ \(Int(goal)) g")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            ProgressBar(
                value: goal > 0 ? value / goal : 0,
                color: Theme.Colors.nutrition,
                height: 5
            )
        }
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
