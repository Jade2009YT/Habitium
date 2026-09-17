//
//  WatchHealthAccess.swift
//  Habitium
//
//  Los permisos que hacen falta para usar los datos del Apple Watch, y
//  la lectura de lo que el reloj ya ha medido.
//
//  Por qué esto importa para la nutrición: la IA que mira la foto sabe
//  estimar lo que COMES, pero no tiene ni idea de lo que GASTAS. Sin el
//  reloj, las calorías gastadas son una fórmula con tu peso y tu edad —
//  una media de una persona que no eres tú. Con el reloj son tus
//  pulsaciones y tu movimiento de hoy. Son las dos mitades de la misma
//  cuenta, y por eso la app pide las dos cosas en vez de elegir una.
//
//  Sobre los permisos, dos cosas que iOS impone y conviene saber:
//
//  1. **Solo se puede preguntar una vez.** Si dices que no, la siguiente
//     llamada a `requestAuthorization` vuelve sin preguntar nada. Por eso
//     Ajustes enseña la ruta a mano (Ajustes → Salud → Acceso de apps)
//     en vez de un botón de reintentar que no haría nada.
//  2. **Nunca te dice si dijiste que sí a LEER.** `authorizationStatus`
//     solo es fiable para escribir; para leer, Apple devuelve siempre
//     "no determinado" a propósito, para que una app no pueda deducir
//     que tienes una condición médica por el hecho de que le niegues un
//     dato concreto. Así que aquí se comprueba de la única forma que
//     funciona: pidiendo permiso y luego INTENTANDO leer algo.
//

import Foundation
import HealthKit
import UserNotifications

@MainActor
enum WatchHealthAccess {

    private static let store = HKHealthStore()

    /// Lo que se pide leer. Corto a propósito: cuantos menos datos pidas,
    /// más gente dice que sí, y estos cuatro son los únicos que la app
    /// usa de verdad.
    private static var readTypes: Set<HKObjectType> {
        var tipos: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let activa = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { tipos.insert(activa) }
        if let basal = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned) { tipos.insert(basal) }
        if let pasos = HKQuantityType.quantityType(forIdentifier: .stepCount) { tipos.insert(pasos) }
        return tipos
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Pide permiso de Salud y de notificaciones, y confirma que de
    /// verdad se puede leer algo. Devuelve false si falta cualquiera de
    /// las dos, para que Ajustes pueda decirlo en vez de quedarse con un
    /// interruptor encendido que no hace nada.
    @discardableResult
    static func requestPermissions() async -> Bool {
        guard isAvailable else { return false }

        // Las notificaciones van primero y aparte: aunque Salud falle, los
        // recordatorios de medicación y comidas siguen teniendo sentido.
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            return false
        }

        return await canActuallyRead()
    }

    /// La comprobación honesta: intentar leer. Si Salud devuelve datos —o
    /// devuelve vacío sin error— el permiso está dado. Si da error de
    /// autorización, no lo está.
    private static func canActuallyRead() async -> Bool {
        guard let tipo = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return false }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: tipo,
                quantitySamplePredicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.startOfDay(for: .now),
                    end: .now
                ),
                options: .cumulativeSum
            ) { _, _, error in
                let denegado = (error as? HKError)?.code == .errorAuthorizationDenied
                    || (error as? HKError)?.code == .errorAuthorizationNotDetermined
                continuation.resume(returning: !denegado)
            }
            store.execute(query)
        }
    }

    /// Calorías gastadas hoy según el reloj (activas + basales).
    /// `nil` cuando no hay permiso o no hay datos: la interfaz debe poder
    /// distinguir "no lo sé" de "cero", que no es lo mismo.
    static func caloriesBurnedToday() async -> Double? {
        guard isAvailable else { return nil }

        let inicio = Calendar.current.startOfDay(for: .now)
        let predicado = HKQuery.predicateForSamples(withStart: inicio, end: .now)

        async let activa = sum(.activeEnergyBurned, predicate: predicado)
        async let basal = sum(.basalEnergyBurned, predicate: predicado)

        let (a, b) = await (activa, basal)
        guard a != nil || b != nil else { return nil }
        return (a ?? 0) + (b ?? 0)
    }

    private static func sum(
        _ identifier: HKQuantityTypeIdentifier,
        predicate: NSPredicate
    ) async -> Double? {
        guard let tipo = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: tipo,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, resultado, _ in
                continuation.resume(
                    returning: resultado?.sumQuantity()?.doubleValue(for: .kilocalorie())
                )
            }
            store.execute(query)
        }
    }
}
