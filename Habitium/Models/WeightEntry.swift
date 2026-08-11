//
//  WeightEntry.swift
//  Habitium
//
//  A single body-weight measurement. Kept as its own append-only log (like
//  PlateLens/Lose It!'s weight trend) rather than a single "current
//  weight" field, so FoodTrackerView can show a trend line instead of just
//  a snapshot.
//

import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID
    var date: Date
    var weightKg: Double

    init(id: UUID = UUID(), date: Date = .now, weightKg: Double) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
    }
}
