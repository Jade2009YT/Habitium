//
//  WorkoutSessionManager.swift
//  HabitiumWatch
//
//  Wraps HKWorkoutSession + HKLiveWorkoutBuilder. Starting a real workout
//  session isn't optional ceremony here — it's what grants the watchOS
//  app continuous background access to the motion sensors while the
//  screen is off or the wrist is down mid-set. Without it, CoreMotion
//  updates get suspended and rep counting would stop the moment the
//  screen dims.
//

import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class WorkoutSessionManager: NSObject {

    enum State: Equatable {
        case idle
        case requestingAuthorization
        case active
        case ended
        case error(String)
    }

    private(set) var state: State = .idle

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isAuthorizationAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func start() {
        guard isAuthorizationAvailable else {
            state = .error("Salud no está disponible en este dispositivo.")
            return
        }

        state = .requestingAuthorization
        let shareTypes: Set = [HKObjectType.workoutType()]
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate) ?? HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) ?? HKObjectType.workoutType()
        ]

        // Bind self to a `let` out here, before the Task — referencing the
        // closure's captured `self` var from inside concurrently-executing
        // code is a warning today and an error in Swift 6. This class is
        // @MainActor, so it's implicitly Sendable and safe to hold onto.
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            guard let self else { return }
            Task { @MainActor in
                guard success else {
                    self.state = .error(error?.localizedDescription ?? "Permiso de Salud denegado.")
                    return
                }
                self.beginSession()
            }
        }
    }

    private func beginSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { [weak self] success, error in
                guard let self else { return }
                Task { @MainActor in
                    self.state = success ? .active : .error(error?.localizedDescription ?? "No se pudo iniciar el entrenamiento.")
                }
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func end() {
        guard let session, let builder else { return }
        session.end()
        let endDate = Date()
        builder.endCollection(withEnd: endDate) { [weak self] _, _ in
            guard let self else { return }
            builder.finishWorkout { _, _ in
                Task { @MainActor in
                    self.state = .ended
                    self.session = nil
                    self.builder = nil
                }
            }
        }
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
