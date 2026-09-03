//
//  ProgressionRepository.swift
//  Habitium
//
//  Concede experiencia, lleva la racha diaria y desbloquea recompensas.
//  Es el único sitio que escribe en PlayerProfile/XPEvent, para que las
//  reglas anti-abuso vivan en un solo lugar y no repartidas por cada
//  repositorio que quiere premiar algo.
//
//  Tres reglas que sostienen todo el sistema:
//
//  1. Nada se premia dos veces. Cada concesión lleva una clave única
//     ("habit:<id>:2026-09-03"); si ya existe, no se da nada. Sin esto,
//     marcar y desmarcar un hábito sería una máquina de XP infinita.
//  2. Solo se premia lo que suma, no lo que se deshace. Desmarcar no
//     resta: castigar un error de pulsación haría que la gente evitara
//     tocar la app, que es lo contrario de lo que se busca.
//  3. La racha se mide en días naturales locales, no en horas. Entrar a
//     las 23:50 y otra vez a las 00:10 son dos días seguidos, y así debe
//     contarse.
//

import Foundation
import SwiftData

/// Lo que hay que enseñar tras conceder experiencia — para el aviso
/// emergente y la animación de subida de nivel.
struct XPAward: Equatable {
    var source: XPSource
    var amount: Int
    var didLevelUp: Bool
    var newLevel: Int
    var unlockedTiers: [String]
}

@MainActor
protocol ProgressionRepository {
    func profile() -> PlayerProfile
    /// Concede experiencia si `dedupeKey` no se había premiado ya.
    /// Devuelve nil cuando no se concedió nada (repetido).
    @discardableResult
    func award(_ source: XPSource, dedupeKey: String, on date: Date) -> XPAward?
    /// Registra el acceso del día: actualiza la racha y premia por entrar.
    @discardableResult
    func registerDailyLogin(on date: Date) -> XPAward?
    /// Últimos eventos, del más reciente al más antiguo.
    func recentEvents(limit: Int) -> [XPEvent]
    /// Experiencia conseguida cada uno de los últimos `days` días, del
    /// más antiguo al más reciente — para el gráfico de la semana.
    func dailyXP(lastDays days: Int) -> [(date: Date, xp: Int)]
}

@MainActor
final class SwiftDataProgressionRepository: ProgressionRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func profile() -> PlayerProfile {
        if let existing = try? context.fetch(FetchDescriptor<PlayerProfile>()).first {
            rolloverSeasonIfNeeded(existing)
            return existing
        }
        let profile = PlayerProfile()
        context.insert(profile)
        save()
        return profile
    }

    @discardableResult
    func award(_ source: XPSource, dedupeKey: String, on date: Date = .now) -> XPAward? {
        guard !hasAwarded(dedupeKey: dedupeKey) else { return nil }

        let profile = self.profile()
        let levelBefore = ProgressionEngine.level(forTotalXP: profile.totalXP)
        let tiersBefore = Set(SeasonPass.unlockedTiers(seasonXP: profile.seasonXP).map(\.id))

        let amount = source.xp
        context.insert(XPEvent(source: source, amount: amount, date: date, dedupeKey: dedupeKey))
        profile.totalXP += amount
        profile.seasonXP += amount
        profile.updatedAt = .now

        let tiersAfter = SeasonPass.unlockedTiers(seasonXP: profile.seasonXP)
        let newTierIDs = tiersAfter.map(\.id).filter { !tiersBefore.contains($0) }
        for id in newTierIDs where !profile.unlockedRewardIDs.contains(id) {
            profile.unlockedRewardIDs.append(id)
        }

        save()

        let levelAfter = ProgressionEngine.level(forTotalXP: profile.totalXP)
        return XPAward(
            source: source,
            amount: amount,
            didLevelUp: levelAfter > levelBefore,
            newLevel: levelAfter,
            unlockedTiers: newTierIDs
        )
    }

    @discardableResult
    func registerDailyLogin(on date: Date = .now) -> XPAward? {
        let profile = self.profile()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        if let last = profile.lastLoginDate {
            let lastDay = calendar.startOfDay(for: last)
            guard lastDay != today else { return nil } // ya contado hoy

            let daysApart = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            // Exactamente un día = sigue la racha. Más de uno = se rompió
            // y vuelve a empezar en 1 (hoy cuenta como el primer día).
            profile.loginStreak = daysApart == 1 ? profile.loginStreak + 1 : 1
        } else {
            profile.loginStreak = 1
        }

        profile.lastLoginDate = today
        profile.longestLoginStreak = max(profile.longestLoginStreak, profile.loginStreak)
        profile.updatedAt = .now
        save()

        // Ojo con el nombre: llamarlo `award` taparía al método del mismo
        // nombre y la llamada del hito de abajo dejaría de compilar.
        let loginAward = award(.dailyLogin, dedupeKey: Self.key("login", on: today), on: date)

        // Un hito de racha se premia aparte, para que además del XP haya
        // un momento reconocible ("¡7 días seguidos!").
        if ProgressionEngine.isStreakMilestone(profile.loginStreak) {
            let milestone = award(
                .streakMilestone,
                dedupeKey: Self.key("streak-\(profile.loginStreak)", on: today),
                on: date
            )
            // Si ambos se concedieron, se devuelve el del hito: es el que
            // merece celebrarse en pantalla.
            if let milestone { return milestone }
        }

        return loginAward
    }

    func recentEvents(limit: Int) -> [XPEvent] {
        var descriptor = FetchDescriptor<XPEvent>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func dailyXP(lastDays days: Int) -> [(date: Date, xp: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        let descriptor = FetchDescriptor<XPEvent>(
            predicate: #Predicate<XPEvent> { $0.date >= start }
        )
        let events = (try? context.fetch(descriptor)) ?? []

        var totals: [Date: Int] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            totals[day, default: 0] += event.amount
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return (date: day, xp: totals[day] ?? 0)
        }
    }

    // MARK: - Claves

    /// "habit:<id>:2026-09-03" — el formato que usan todas las llamadas.
    static func key(_ prefix: String, on date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%@:%04d-%02d-%02d",
            prefix,
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    // MARK: - Privado

    private func hasAwarded(dedupeKey: String) -> Bool {
        let descriptor = FetchDescriptor<XPEvent>(
            predicate: #Predicate<XPEvent> { $0.dedupeKey == dedupeKey }
        )
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    /// Al entrar en un mes nuevo, la experiencia de temporada vuelve a
    /// cero. Lo desbloqueado se conserva a propósito (ver SeasonPass).
    private func rolloverSeasonIfNeeded(_ profile: PlayerProfile) {
        let current = PlayerProfile.currentSeasonID()
        guard profile.seasonID != current else { return }
        profile.seasonID = current
        profile.seasonXP = 0
        profile.updatedAt = .now
        save()
    }

    private func save() {
        try? context.save()
    }
}
