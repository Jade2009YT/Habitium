//
//  LoggedWorkoutSet.swift
//  Habitium (shared between the iOS app and the watchOS app ONLY)
//
//  One completed set (exercise + rep count), created on the Watch by
//  RepCounter/WorkoutView and sent to the iPhone over WatchConnectivity
//  to be persisted into SwiftData — see WatchConnectivityBridge and
//  WorkoutRepository.
//

import Foundation

struct LoggedWorkoutSet: Codable, Identifiable, Equatable {
    var id = UUID()
    var exerciseName: String
    var reps: Int
    var date: Date
}
