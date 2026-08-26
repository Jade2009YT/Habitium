//
//  WorkoutSet.swift
//  Habitium
//
//  One completed set logged from the Apple Watch's CoreMotion rep counter
//  (see HabitiumWatch/RepCounter.swift + WorkoutView.swift). Arrives over
//  WatchConnectivity as a LoggedWorkoutSet and is persisted here by
//  WorkoutRepository — this table is the iPhone-side source of truth;
//  LoggedWorkoutSet is only the wire format between the two devices.
//

import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var id: UUID
    var exerciseName: String
    var reps: Int
    var date: Date
    /// See FoodEntry.updatedAt — same purpose, for CloudSyncService.
    var updatedAt: Date

    init(id: UUID = UUID(), exerciseName: String, reps: Int, date: Date, updatedAt: Date = .now) {
        self.id = id
        self.exerciseName = exerciseName
        self.reps = reps
        self.date = date
        self.updatedAt = updatedAt
    }
}
