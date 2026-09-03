//
//  ProgressionViewModel.swift
//  Habitium
//
//  Traduce PlayerProfile + XPEvent a lo que pinta ProgressionView, y es
//  también quien resuelve el color de acento activo (el tema elegido en
//  Ajustes, siempre que siga desbloqueado).
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ProgressionViewModel {

    private(set) var totalXP: Int = 0
    private(set) var seasonXP: Int = 0
    private(set) var seasonID: String = ""
    private(set) var loginStreak: Int = 0
    private(set) var longestStreak: Int = 0
    private(set) var unlockedRewardIDs: [String] = []
    private(set) var recentEvents: [XPEvent] = []
    private(set) var weeklyXP: [(date: Date, xp: Int)] = []

    private let container: AppDependencyContainer

    init(container: AppDependencyContainer) {
        self.container = container
        refresh()
    }

    func refresh() {
        let profile = container.progressionRepository.profile()
        totalXP = profile.totalXP
        seasonXP = profile.seasonXP
        seasonID = profile.seasonID
        loginStreak = profile.loginStreak
        longestStreak = profile.longestLoginStreak
        unlockedRewardIDs = profile.unlockedRewardIDs
        recentEvents = container.progressionRepository.recentEvents(limit: 12)
        weeklyXP = container.progressionRepository.dailyXP(lastDays: 7)
    }

    // MARK: - Nivel

    var level: Int { ProgressionEngine.level(forTotalXP: totalXP) }
    var levelTitle: String { ProgressionEngine.title(forLevel: level) }
    var levelProgress: Double { ProgressionEngine.progressWithinLevel(totalXP: totalXP) }
    var xpToNextLevel: Int { ProgressionEngine.xpRemainingToNextLevel(totalXP: totalXP) }

    // MARK: - Racha

    var nextStreakMilestone: Int? {
        ProgressionEngine.streakMilestones.first { $0 > loginStreak }
    }

    // MARK: - Temporada

    var nextTier: SeasonTier? { SeasonPass.nextTier(seasonXP: seasonXP) }

    func isUnlocked(_ tier: SeasonTier) -> Bool {
        unlockedRewardIDs.contains(tier.id) || seasonXP >= tier.xpRequired
    }

    var earnedTitle: String? { SeasonPass.highestTitle(unlockedRewardIDs: unlockedRewardIDs) }

    /// "septiembre" — el nombre del mes de la temporada, a partir del id
    /// "2026-09".
    var seasonName: String {
        let parts = seasonID.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1]))
        else { return "temporada" }
        return date.formatted(.dateTime.month(.wide))
    }

    // MARK: - Acento

    /// El tema elegido en Ajustes, si sigue desbloqueado. Si alguien
    /// eligiera uno y luego se borrara el progreso, esto vuelve al
    /// clásico en vez de dejar la app con un color al que ya no tiene
    /// derecho.
    var accentColor: Color {
        let stored = UserDefaults.standard.string(forKey: AccentThemeStore.defaultsKey)
        guard let theme = stored.flatMap(AccentTheme.init(rawValue:)),
              SeasonPass.availableAccents(unlockedRewardIDs: unlockedRewardIDs).contains(theme)
        else { return AccentTheme.classic.color }
        return theme.color
    }
}

/// Dónde vive el tema elegido. Es una preferencia de aspecto de este
/// dispositivo, así que UserDefaults basta — no merece una tabla ni
/// viajar por la sincronización.
enum AccentThemeStore {
    static let defaultsKey = "habitium.accentTheme"

    static var current: AccentTheme {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(AccentTheme.init(rawValue:)) ?? .classic
    }

    static func set(_ theme: AccentTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: defaultsKey)
    }
}
