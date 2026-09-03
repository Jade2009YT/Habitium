//
//  PlayerProfile.swift
//  Habitium
//
//  El progreso del usuario: nivel, experiencia, racha de días seguidos y
//  lo desbloqueado en el pase de temporada.
//
//  Por qué existe XPEvent aparte del total: sin un registro de qué se ha
//  premiado ya, sería trivial farmear XP marcando y desmarcando el mismo
//  hábito veinte veces. Cada evento lleva una `dedupeKey` (por ejemplo
//  "habit:<id>:2026-09-03") y el repositorio se niega a premiar dos veces
//  la misma clave. Además da un historial real para la pantalla de
//  progreso, en vez de un número que sube sin explicación.
//

import Foundation
import SwiftData

/// De dónde salió la experiencia. El valor en bruto se guarda en la base
/// de datos, así que añadir casos es seguro pero renombrarlos no.
enum XPSource: String, Codable, CaseIterable {
    case dailyLogin
    case habitCompleted
    case allHabitsCompleted
    case mealLogged
    case taskCompleted
    case focusTaskCompleted
    case medicationTaken
    case workoutLogged
    case weightLogged
    case streakMilestone
    case dailyChallenge

    var displayName: String {
        switch self {
        case .dailyLogin: return "Entrar cada día"
        case .habitCompleted: return "Hábito cumplido"
        case .allHabitsCompleted: return "Todos los hábitos del día"
        case .mealLogged: return "Comida registrada"
        case .taskCompleted: return "Tarea completada"
        case .focusTaskCompleted: return "Foco del día completado"
        case .medicationTaken: return "Medicación tomada"
        case .workoutLogged: return "Entrenamiento registrado"
        case .weightLogged: return "Peso registrado"
        case .streakMilestone: return "Hito de racha"
        case .dailyChallenge: return "Retos del día completados"
        }
    }

    var symbolName: String {
        switch self {
        case .dailyLogin: return "sun.max.fill"
        case .habitCompleted, .allHabitsCompleted: return "repeat.circle.fill"
        case .mealLogged: return "fork.knife"
        case .taskCompleted, .focusTaskCompleted: return "checklist"
        case .medicationTaken: return "pills.fill"
        case .workoutLogged: return "figure.strengthtraining.traditional"
        case .weightLogged: return "scalemass.fill"
        case .streakMilestone: return "flame.fill"
        case .dailyChallenge: return "target"
        }
    }

    /// Cuánta experiencia da. Los valores están calibrados para que el
    /// esfuerzo mande sobre el relleno: registrar una comida da poco,
    /// cerrar TODOS los hábitos del día da mucho. Si diera lo mismo,
    /// lo óptimo sería registrar veinte comidas y no cumplir nada.
    var xp: Int {
        switch self {
        case .dailyLogin: return 10
        case .habitCompleted: return 15
        case .allHabitsCompleted: return 40
        case .mealLogged: return 5
        case .taskCompleted: return 10
        case .focusTaskCompleted: return 20
        case .medicationTaken: return 10
        case .workoutLogged: return 30
        case .weightLogged: return 5
        case .streakMilestone: return 50
        case .dailyChallenge: return DailyChallengeEngine.bonusXP
        }
    }
}

@Model
final class PlayerProfile {
    var id: UUID
    var totalXP: Int
    /// Días seguidos abriendo la app. Se rompe al saltarse un día entero.
    var loginStreak: Int
    var longestLoginStreak: Int
    /// Inicio del día del último acceso — para saber si la racha sigue.
    var lastLoginDate: Date?
    /// Temporada activa, con formato "2026-09". El pase se reinicia cada
    /// mes natural: una temporada que no termina nunca deja de motivar.
    var seasonID: String
    var seasonXP: Int
    /// Identificadores de recompensas ya desbloqueadas (ver SeasonPass).
    var unlockedRewardIDs: [String]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        totalXP: Int = 0,
        loginStreak: Int = 0,
        longestLoginStreak: Int = 0,
        lastLoginDate: Date? = nil,
        seasonID: String = PlayerProfile.currentSeasonID(),
        seasonXP: Int = 0,
        unlockedRewardIDs: [String] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.totalXP = totalXP
        self.loginStreak = loginStreak
        self.longestLoginStreak = longestLoginStreak
        self.lastLoginDate = lastLoginDate
        self.seasonID = seasonID
        self.seasonXP = seasonXP
        self.unlockedRewardIDs = unlockedRewardIDs
        self.updatedAt = updatedAt
    }

    /// "2026-09" para la fecha dada. Se calcula con el calendario local:
    /// la temporada debe cambiar cuando cambia el mes para el usuario, no
    /// en UTC.
    static func currentSeasonID(for date: Date = .now) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}

/// Una concesión de experiencia. `dedupeKey` es lo que impide premiar dos
/// veces lo mismo.
@Model
final class XPEvent {
    var id: UUID
    var source: XPSource.RawValue
    var amount: Int
    var date: Date
    /// Única por "cosa premiable": "habit:<id>:2026-09-03", "login:2026-09-03".
    var dedupeKey: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        source: XPSource,
        amount: Int,
        date: Date = .now,
        dedupeKey: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.source = source.rawValue
        self.amount = amount
        self.date = date
        self.dedupeKey = dedupeKey
        self.updatedAt = updatedAt
    }
}
