//
//  DailyChallengeService.swift
//  Habitium
//
//  Mide el progreso de los retos de hoy contra los datos reales, y
//  concede la bonificación cuando se completan los tres.
//
//  No guarda nada: el progreso se calcula mirando lo que ya hay
//  (hábitos cumplidos hoy, tareas completadas hoy, comidas registradas
//  hoy). Guardar un contador aparte sería una segunda fuente de verdad
//  que se desincronizaría en cuanto alguien borrase una comida.
//

import Foundation
import SwiftData

@MainActor
final class DailyChallengeService {

    private let context: ModelContext
    private let habitRepository: HabitRepository
    private let medicationRepository: MedicationRepository
    private let progression: ProgressionRepository

    init(
        context: ModelContext,
        habitRepository: HabitRepository,
        medicationRepository: MedicationRepository,
        progression: ProgressionRepository
    ) {
        self.context = context
        self.habitRepository = habitRepository
        self.medicationRepository = medicationRepository
        self.progression = progression
    }

    /// Los retos de hoy con su progreso al día.
    func todaysChallenges(now: Date = .now) -> [DailyChallenge] {
        DailyChallengeEngine.challenges(for: now).map { challenge in
            var updated = challenge
            updated.progress = progress(for: challenge.kind, now: now)
            return updated
        }
    }

    /// Comprueba si están los tres y, en ese caso, concede la
    /// bonificación. La clave incluye el día, así que solo se cobra una
    /// vez. Devuelve la concesión para poder celebrarla.
    @discardableResult
    func awardBonusIfComplete(now: Date = .now) -> XPAward? {
        let challenges = todaysChallenges(now: now)
        guard !challenges.isEmpty, challenges.allSatisfy(\.isComplete) else { return nil }
        return progression.award(
            .dailyChallenge,
            dedupeKey: SwiftDataProgressionRepository.key("challenges", on: now),
            on: now
        )
    }

    // MARK: - Medición

    private func progress(for kind: DailyChallenge.Kind, now: Date) -> Int {
        switch kind {
        case .habits:
            return habitRepository.todaysStatuses().filter(\.isGoalMetToday).count

        case .focus:
            // updatedAt es la fecha del último cambio, así que para una
            // tarea completada equivale a "cuándo se completó" — que es
            // justo lo que hay que contar hoy.
            return countToday(FetchDescriptor<PlannerTask>(
                predicate: #Predicate<PlannerTask> { $0.isFocus && $0.isCompleted }
            ), now: now, dateOf: { $0.updatedAt })

        case .tasks:
            return countToday(FetchDescriptor<PlannerTask>(
                predicate: #Predicate<PlannerTask> { $0.isCompleted }
            ), now: now, dateOf: { $0.updatedAt })

        case .meals:
            return countToday(FetchDescriptor<FoodEntry>(), now: now, dateOf: { $0.date })

        case .weight:
            return countToday(FetchDescriptor<WeightEntry>(), now: now, dateOf: { $0.date })

        case .workout:
            return countToday(FetchDescriptor<WorkoutSet>(), now: now, dateOf: { $0.date }) > 0 ? 1 : 0

        case .medication:
            let doses = medicationRepository.todaysDoses()
            // Sin medicación configurada el reto no aplica; se da por
            // cumplido en vez de dejarlo imposible para siempre.
            guard !doses.isEmpty else { return 1 }
            return doses.allSatisfy { $0.isTaken || $0.isSkipped } ? 1 : 0
        }
    }

    /// Cuenta filas cuya fecha cae hoy. El filtro por día se hace en
    /// memoria a propósito: #Predicate no admite comparar contra un rango
    /// calculado dentro del propio predicado sin complicarlo mucho, y
    /// estos conjuntos son de decenas de filas, no de miles.
    private func countToday<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        now: Date,
        dateOf: (T) -> Date
    ) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.filter { calendar.startOfDay(for: dateOf($0)) == today }.count
    }
}
