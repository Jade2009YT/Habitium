//
//  RoutineNotifications.swift
//  Habitium
//
//  Los avisos encadenados de una rutina: "levántate" a las 7:15, "dúchate"
//  a las 7:25, y así.
//
//  ── Aquí es donde el iPhone gana a la web, y por mucho ─────────────
//
//  Una página web NO puede programar una notificación para dentro de tres
//  horas y desentenderse: la API que hacía eso se retiró de Chrome y no
//  está en ningún navegador. Sin un servidor propio que empuje
//  notificaciones push, lo máximo que puede hacer la web es avisar
//  mientras está abierta (ver web/avisos.js, que lo dice sin disimular).
//
//  Aquí no: `UNUserNotificationCenter` las entrega con la app cerrada, el
//  móvil bloqueado y el usuario dormido. Que es justamente el caso de una
//  rutina de mañana.
//
//  ── Las dos decisiones que tiene esto ──────────────────────────────
//
//  1. Se programan varios días por adelantado, no solo hoy. Si solo se
//     programara hoy y el usuario no abriera la app por la noche, mañana
//     no sonaría nada — y una rutina de mañana que no suena es una rutina
//     que no existe.
//
//  2. Pero no muchos: iOS admite 64 notificaciones pendientes por app y
//     tira las que sobran SIN avisar. Con `diasPorDelante = 3` y el resto
//     de avisos de Habitium (medicación, tareas, comidas) el presupuesto
//     cuadra; subirlo es arriesgarse a que se caigan las de otro sitio.
//
//  Los avisos de HOY se recalculan cada vez que se marca un paso (porque
//  marcar mueve en cascada todos los siguientes). Los de los días
//  siguientes van con la hora teórica: no se puede saber a qué hora te
//  vas a duchar pasado mañana.
//

import Foundation
import UserNotifications

extension NotificationScheduler {

    /// Cuántos días por delante se programan. Ver el comentario de arriba
    /// antes de tocarlo: el límite de 64 de iOS no avisa cuando se pasa.
    static let routineDaysAhead = 3

    /// Prefijo de los identificadores, para poder cancelar solo los de una
    /// rutina sin tocar los de medicación ni los de la agenda.
    private static func routinePrefix(_ routineID: UUID) -> String {
        "rutina.\(routineID.uuidString)."
    }

    /// Reprograma TODOS los avisos de una rutina desde cero.
    ///
    /// Rehace todo en vez de ir tocando lo que cambió, y es a propósito:
    /// el horario se recalcula en cascada (marcar un paso mueve todos los
    /// siguientes), así que rehacerlo entero es más simple Y más correcto
    /// que adivinar qué avisos siguen valiendo.
    ///
    /// Devuelve los identificadores nuevos para guardarlos en la Routine.
    @discardableResult
    func rescheduleRoutine(
        _ routine: Routine,
        steps: [RoutineStep],
        logs: [RoutineLog],
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> [String] {
        // Fuera lo viejo. Se busca por prefijo en vez de fiarse de lo que
        // había guardado en la rutina: si la app murió a medio programar,
        // los identificadores guardados podrían no ser todos los que hay.
        let prefix = Self.routinePrefix(routine.id)
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        guard routine.isActive, routine.notificationsEnabled else { return [] }

        var created: [String] = []

        for dayOffset in 0..<Self.routineDaysAhead {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard RoutineSchedule.occurs(routine, on: day, calendar: calendar) else { continue }

            // Solo el día de hoy usa los pasos ya marcados para recalcular.
            // Para mañana no se puede saber a qué hora te vas a duchar, así
            // que va la hora teórica.
            let logsForDay = dayOffset == 0 ? logs : []

            let entries = RoutineSchedule.entries(
                for: routine, steps: steps, logs: logsForDay,
                now: now, on: day, calendar: calendar
            )

            let remaining = entries.filter { !$0.isDone }

            for (index, entry) in remaining.enumerated() {
                guard entry.time > now else { continue }   // lo que ya pasó, no se resucita

                let identifier = "\(prefix)\(entry.step.id.uuidString).\(dayOffset)"
                let content = UNMutableNotificationContent()
                content.title = "\(entry.step.icon) \(entry.step.title)"
                content.body = Self.bodyText(routine: routine, left: remaining.count - index - 1)
                content.sound = .default
                // El threadIdentifier agrupa los avisos de la misma rutina
                // en la pantalla de bloqueo: cuatro notificaciones sueltas
                // a las siete de la mañana son cuatro interrupciones; una
                // pila con cuatro dentro es una.
                content.threadIdentifier = "rutina.\(routine.id.uuidString)"
                content.userInfo = [
                    "routineID": routine.id.uuidString,
                    "stepID": entry.step.id.uuidString,
                ]

                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: entry.time
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                created.append(identifier)
            }
        }

        return created
    }

    /// Quita los avisos de una rutina borrada.
    func cancelRoutine(_ routineID: UUID) async {
        let prefix = Self.routinePrefix(routineID)
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    private static func bodyText(routine: Routine, left: Int) -> String {
        switch left {
        case 0: return "Último paso de \(routine.name). Ya está."
        case 1: return "\(routine.name) · Queda uno más."
        default: return "\(routine.name) · Quedan \(left) más."
        }
    }
}
