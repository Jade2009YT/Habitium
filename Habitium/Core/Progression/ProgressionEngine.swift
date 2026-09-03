//
//  ProgressionEngine.swift
//  Habitium
//
//  Las matemáticas de niveles. Sin estado y sin dependencias a propósito:
//  es la parte que más fácil es equivocar y la única del sistema de
//  progresión que se puede probar sola (ver HabitiumTests).
//
//  Forma de la curva: cada nivel cuesta 100 + (nivel-1)*50 de experiencia.
//  Nivel 1→2 son 100, 2→3 son 150, 3→4 son 200… Crece lo justo para que
//  subir siga costando más sin volverse imposible: con un uso normal
//  (entrar, cumplir hábitos, alguna tarea) salen unos 100-150 XP al día,
//  o sea un nivel diario al principio y cada pocos días más adelante.
//  Una curva exponencial se atasca enseguida; una plana deja de premiar.
//

import Foundation

enum ProgressionEngine {

    /// Experiencia necesaria para pasar de `level` al siguiente.
    static func xpToAdvance(fromLevel level: Int) -> Int {
        max(1, 100 + (level - 1) * 50)
    }

    /// Experiencia total acumulada necesaria para alcanzar `level`.
    /// Nivel 1 es el inicial, así que cuesta 0.
    static func totalXPRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1..<level).reduce(0) { $0 + xpToAdvance(fromLevel: $1) }
    }

    /// Nivel correspondiente a una experiencia total.
    static func level(forTotalXP xp: Int) -> Int {
        guard xp > 0 else { return 1 }
        var level = 1
        var remaining = xp
        while remaining >= xpToAdvance(fromLevel: level) {
            remaining -= xpToAdvance(fromLevel: level)
            level += 1
        }
        return level
    }

    /// Progreso dentro del nivel actual, de 0 a 1 — para la barra.
    static func progressWithinLevel(totalXP: Int) -> Double {
        let level = level(forTotalXP: totalXP)
        let earned = totalXP - totalXPRequired(forLevel: level)
        let needed = xpToAdvance(fromLevel: level)
        return needed > 0 ? min(max(Double(earned) / Double(needed), 0), 1) : 0
    }

    /// Cuánta experiencia falta para el siguiente nivel.
    static func xpRemainingToNextLevel(totalXP: Int) -> Int {
        let level = level(forTotalXP: totalXP)
        let earned = totalXP - totalXPRequired(forLevel: level)
        return max(0, xpToAdvance(fromLevel: level) - earned)
    }

    /// Título que acompaña al nivel. Da una meta con nombre además del
    /// número: "Nivel 12" dice menos que "Constante".
    static func title(forLevel level: Int) -> String {
        switch level {
        case ..<3: return "Empezando"
        case 3..<6: return "Cogiendo ritmo"
        case 6..<10: return "Constante"
        case 10..<15: return "En racha"
        case 15..<25: return "Imparable"
        case 25..<40: return "Referente"
        default: return "Leyenda"
        }
    }

    /// Hitos de racha que dan experiencia extra. Están espaciados para
    /// que siempre haya uno cerca sin que lleguen a ser rutina.
    static let streakMilestones = [3, 7, 14, 30, 60, 100, 180, 365]

    static func isStreakMilestone(_ days: Int) -> Bool {
        streakMilestones.contains(days)
    }
}
