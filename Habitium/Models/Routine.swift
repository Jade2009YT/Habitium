//
//  Routine.swift
//  Habitium
//
//  Una rutina encadenada: "a las 7:15 me levanto, luego me ducho, luego
//  me lavo los dientes, luego desayuno".
//
//  ── Por qué se guarda así y no de otra forma ───────────────────────
//
//  La rutina tiene UNA hora de inicio y cada paso tiene una DURACIÓN. No
//  hay una hora guardada por paso, y es a propósito:
//
//    · Con una hora fija en cada paso, el día que te levantas diez
//      minutos tarde todos los avisos van desfasados y acabas
//      silenciándolos. Y el día que te duchas rápido, esperas mirando el
//      móvil.
//    · Con encadenado puro (cada paso arranca al marcar el anterior), el
//      PRIMER aviso no suena nunca: no hay nada que marcar antes de él.
//
//  Con inicio + duraciones se hacen las dos cosas: los avisos salen a la
//  hora calculada, y al marcar un paso los que quedan se recalculan desde
//  ese instante real. Ver RoutineSchedule, que es donde está el cálculo,
//  y su gemelo en web/routines.js — los dos siguen la misma regla porque
//  la misma cuenta tiene que ver lo mismo en los dos sitios.
//
//  `startMinutes` son minutos desde medianoche (7:15 → 435) en vez de una
//  Date: una rutina de mañana es a las 7:15 estés donde estés, no "a las
//  5:15 UTC". Es lo mismo que ya hace Medication.
//

import Foundation
import SwiftData

@Model
final class Routine {
    var id: UUID
    var name: String
    var icon: String
    /// Minutos desde medianoche. 7:15 → 435.
    var startMinutes: Int
    /// 1 = lunes … 7 = domingo (ISO). Vacío significa todos los días.
    var daysOfWeek: [Int]
    var isActive: Bool
    var notificationsEnabled: Bool
    var sortOrder: Int
    var createdAt: Date
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    /// Los identificadores de las notificaciones programadas AHORA mismo
    /// para esta rutina. No se sincronizan (ver la regla 5 de
    /// supabase/schema.sql): cada dispositivo programa las suyas.
    var notificationIdentifiers: [String]

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "☀️",
        startMinutes: Int = 7 * 60 + 15,
        daysOfWeek: [Int] = [1, 2, 3, 4, 5],
        isActive: Bool = true,
        notificationsEnabled: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        notificationIdentifiers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.startMinutes = startMinutes
        self.daysOfWeek = daysOfWeek
        self.isActive = isActive
        self.notificationsEnabled = notificationsEnabled
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notificationIdentifiers = notificationIdentifiers
    }
}

@Model
final class RoutineStep {
    var id: UUID
    /// El id de la Routine. Se guarda como UUID suelto y no como relación
    /// de SwiftData por lo mismo que en el resto del modelo: el sync sube
    /// filas planas a Postgres, y una relación obligaría a resolverla a
    /// mano en cada dirección.
    var routineID: UUID
    var title: String
    var icon: String
    /// Cuánto dura ESTE paso. El siguiente empieza cuando este acaba.
    var durationMinutes: Int
    var sortOrder: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        routineID: UUID,
        title: String,
        icon: String = "✅",
        durationMinutes: Int = 10,
        sortOrder: Int = 0,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.routineID = routineID
        self.title = title
        self.icon = icon
        self.durationMinutes = durationMinutes
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}

@Model
final class RoutineLog {
    var id: UUID
    var routineID: UUID
    var stepID: UUID
    /// El INSTANTE en que se marcó, no el día. Es lo que permite
    /// recalcular los avisos que quedan.
    var date: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        routineID: UUID,
        stepID: UUID,
        date: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.routineID = routineID
        self.stepID = stepID
        self.date = date
        self.updatedAt = updatedAt
    }
}
