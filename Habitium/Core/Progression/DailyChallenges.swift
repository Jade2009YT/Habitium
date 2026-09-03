//
//  DailyChallenges.swift
//  Habitium
//
//  Tres retos que cambian cada día.
//
//  Es la pieza que ataca el aburrimiento de frente. Nivel y racha premian
//  seguir haciendo lo de siempre; eso mantiene, pero no sorprende. Los
//  retos cambian el objetivo cada mañana ("hoy: 2 tareas y registrar el
//  desayuno"), así que abrir la app tiene algo nuevo aunque tus hábitos
//  sean los mismos de siempre.
//
//  Se eligen de forma determinista a partir de la fecha: el mismo día
//  siempre da los mismos tres retos. Eso importa por dos razones — que no
//  cambien al reabrir la app (sería frustrante perder el progreso de un
//  reto), y que el iPhone y la web muestren lo mismo sin tener que
//  guardar ni sincronizar nada.
//

import Foundation

struct DailyChallenge: Identifiable {
    let kind: Kind
    let goal: Int
    var progress: Int

    var id: String { kind.rawValue }
    var isComplete: Bool { progress >= goal }
    /// De 0 a 1, para la barra.
    var fraction: Double { goal > 0 ? min(Double(progress) / Double(goal), 1) : 0 }

    enum Kind: String, CaseIterable {
        case habits
        case tasks
        case meals
        case medication
        case weight
        case workout
        case focus

        var symbolName: String {
            switch self {
            case .habits: return "repeat.circle.fill"
            case .tasks: return "checklist"
            case .meals: return "fork.knife"
            case .medication: return "pills.fill"
            case .weight: return "scalemass.fill"
            case .workout: return "figure.strengthtraining.traditional"
            case .focus: return "star.fill"
            }
        }

        /// Los objetivos posibles. Se elige uno según el día, para que un
        /// martes pida 2 hábitos y un jueves 4 — si siempre pidiera lo
        /// mismo dejaría de ser un reto y volvería a ser rutina.
        var goalOptions: [Int] {
            switch self {
            case .habits: return [2, 3, 4]
            case .tasks: return [1, 2, 3]
            case .meals: return [2, 3]
            case .medication, .weight, .workout, .focus: return [1]
            }
        }

        func title(goal: Int) -> String {
            switch self {
            case .habits: return goal == 1 ? "Cumple 1 hábito" : "Cumple \(goal) hábitos"
            case .tasks: return goal == 1 ? "Completa 1 tarea" : "Completa \(goal) tareas"
            case .meals: return "Registra \(goal) comidas"
            case .medication: return "Toma toda tu medicación"
            case .weight: return "Registra tu peso"
            case .workout: return "Entrena hoy"
            case .focus: return "Cierra un foco del día"
            }
        }
    }
}

enum DailyChallengeEngine {

    /// Cuánta experiencia extra da completar los tres.
    static let bonusXP = 60

    /// Los tres retos del día, sin progreso todavía.
    ///
    /// El sorteo usa la fecha como semilla mediante un generador propio:
    /// `Int.random` daría resultados distintos en cada llamada, y
    /// `hashValue` de Swift no es estable entre ejecuciones (cambia con
    /// cada arranque por seguridad), así que ninguno de los dos sirve
    /// para "el mismo día, los mismos retos".
    static func challenges(for date: Date = .now) -> [DailyChallenge] {
        var generator = SeededGenerator(seed: daySeed(for: date))

        // Medicación y entrenamiento solo aparecen a veces: pedirlos a
        // diario a quien no toma nada ni entrena sería un reto imposible
        // permanente, que desmotiva más que no tener retos.
        var pool = DailyChallenge.Kind.allCases.filter { $0 != .medication && $0 != .workout }
        if Int.random(in: 0..<3, using: &generator) == 0 { pool.append(.medication) }
        if Int.random(in: 0..<3, using: &generator) == 0 { pool.append(.workout) }

        var chosen: [DailyChallenge.Kind] = []
        while chosen.count < 3 && !pool.isEmpty {
            let index = Int.random(in: 0..<pool.count, using: &generator)
            chosen.append(pool.remove(at: index))
        }

        return chosen.map { kind in
            let options = kind.goalOptions
            let goal = options[Int.random(in: 0..<options.count, using: &generator)]
            return DailyChallenge(kind: kind, goal: goal, progress: 0)
        }
    }

    /// Número estable a partir del día natural: 20260903 para el 3 de
    /// septiembre de 2026.
    private static func daySeed(for date: Date) -> UInt64 {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let value = (components.year ?? 0) * 10000 + (components.month ?? 0) * 100 + (components.day ?? 0)
        return UInt64(max(0, value))
    }
}

/// Generador de números pseudoaleatorios reproducible (SplitMix64). Con
/// la misma semilla da siempre la misma secuencia, que es exactamente lo
/// que necesitan los retos del día.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // El +1 evita el caso degenerado de semilla 0.
        state = seed &+ 1
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
