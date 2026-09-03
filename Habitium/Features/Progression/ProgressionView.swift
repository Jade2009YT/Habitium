//
//  ProgressionView.swift
//  Habitium
//
//  Tu nivel, tu racha y el pase de temporada.
//
//  Ojo con el nombre del archivo y del tipo: NO puede llamarse
//  ProgressView — ese nombre ya es de SwiftUI, y colisionar con él rompe
//  todas las ruedas de carga de la app de forma muy difícil de
//  diagnosticar.
//

import SwiftUI

struct ProgressionView: View {
    @Environment(AppDependencyContainer.self) private var container
    @State private var viewModel: ProgressionViewModel?

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    levelCard(viewModel)
                    streakCard(viewModel)
                    seasonCard(viewModel)
                    weekCard(viewModel)
                    historyCard(viewModel)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            } else {
                SwiftUI.ProgressView().padding(.top, 60)
            }
        }
        .themedBackground()
        .navigationTitle("Progreso")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil {
                viewModel = ProgressionViewModel(container: container)
            } else {
                viewModel?.refresh()
            }
        }
    }

    // MARK: - Nivel

    private func levelCard(_ viewModel: ProgressionViewModel) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RingProgress(
                        progress: viewModel.levelProgress,
                        color: viewModel.accentColor,
                        lineWidth: 10,
                        size: 96
                    )
                    VStack(spacing: -2) {
                        Text("\(viewModel.level)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("nivel")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.levelTitle)
                        .font(.title3.weight(.bold))
                    if let title = viewModel.earnedTitle {
                        Text("«\(title)»")
                            .font(.subheadline)
                            .foregroundStyle(viewModel.accentColor)
                    }
                    Text("\(viewModel.xpToNextLevel) XP para el nivel \(viewModel.level + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.totalXP) XP en total")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
            }
        }
        .cardStyle()
    }

    // MARK: - Racha

    private func streakCard(_ viewModel: ProgressionViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Racha", symbol: "flame.fill", color: Theme.Colors.streak)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(viewModel.loginStreak)")
                    .font(Theme.Fonts.metric)
                    .foregroundStyle(Theme.Colors.streak)
                    .contentTransition(.numericText())
                Text(viewModel.loginStreak == 1 ? "día seguido" : "días seguidos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(viewModel.longestStreak)")
                        .font(.subheadline.weight(.bold))
                    Text("tu récord")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let next = viewModel.nextStreakMilestone {
                let remaining = next - viewModel.loginStreak
                ProgressBar(
                    value: Double(viewModel.loginStreak) / Double(next),
                    color: Theme.Colors.streak
                )
                Text("\(remaining) \(remaining == 1 ? "día" : "días") para el hito de \(next) — +\(XPSource.streakMilestone.xp) XP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Pase de temporada

    private func seasonCard(_ viewModel: ProgressionViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Pase de \(viewModel.seasonName)", symbol: "trophy.fill", color: viewModel.accentColor) {
                Text("\(viewModel.seasonXP) XP")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(viewModel.accentColor)
            }

            if let next = viewModel.nextTier {
                ProgressBar(
                    value: SeasonPass.progressToNextTier(seasonXP: viewModel.seasonXP),
                    color: viewModel.accentColor,
                    height: 9
                )
                Text("\(next.xpRequired - viewModel.seasonXP) XP para \(next.rewardName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("¡Pase completo este mes! 🏆")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.accentColor)
            }

            Divider().padding(.vertical, 2)

            ForEach(SeasonPass.tiers) { tier in
                let unlocked = viewModel.isUnlocked(tier)
                HStack(spacing: 12) {
                    IconBadge(
                        symbol: unlocked ? tier.symbolName : "lock.fill",
                        color: unlocked ? viewModel.accentColor : .secondary,
                        size: 28
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tier.rewardName)
                            .font(.subheadline.weight(unlocked ? .semibold : .regular))
                            .foregroundStyle(unlocked ? .primary : .secondary)
                        Text("Nivel \(tier.tier) · \(tier.xpRequired) XP")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if unlocked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(viewModel.accentColor)
                    }
                }
                .padding(.vertical, 2)
            }

            Text("La temporada se reinicia cada mes, pero lo desbloqueado se queda para siempre.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Semana

    private func weekCard(_ viewModel: ProgressionViewModel) -> some View {
        let maxXP = max(viewModel.weeklyXP.map(\.xp).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Últimos 7 días", symbol: "chart.bar.fill", color: viewModel.accentColor) {
                Text("\(viewModel.weeklyXP.reduce(0) { $0 + $1.xp }) XP")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(viewModel.weeklyXP, id: \.date) { day in
                    VStack(spacing: 5) {
                        // 68 puntos de alto máximo; la barra de un día sin
                        // nada se queda en 3 para que la columna exista.
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(day.xp > 0 ? viewModel.accentColor : Color(.tertiarySystemFill))
                            .frame(height: max(3, CGFloat(day.xp) / CGFloat(maxXP) * 68))
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Historial

    private func historyCard(_ viewModel: ProgressionViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Layout.rowSpacing) {
            CardHeader(title: "Últimos puntos", symbol: "clock.arrow.circlepath", color: .secondary)

            if viewModel.recentEvents.isEmpty {
                EmptyHint(symbol: "sparkles", message: "Aún no has ganado puntos. Cumple un hábito o marca una tarea.")
            } else {
                ForEach(Array(viewModel.recentEvents.enumerated()), id: \.element.id) { index, event in
                    if index > 0 { Divider() }
                    let source = XPSource(rawValue: event.source)
                    HStack(spacing: 11) {
                        IconBadge(
                            symbol: source?.symbolName ?? "sparkles",
                            color: viewModel.accentColor,
                            size: 26
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source?.displayName ?? "Puntos")
                                .font(.subheadline)
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Text("+\(event.amount)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(viewModel.accentColor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

#Preview {
    NavigationStack {
        ProgressionView()
            .environment(AppDependencyContainer(modelContext: PersistenceController.preview().container.mainContext))
    }
}
