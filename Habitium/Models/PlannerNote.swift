//
//  PlannerNote.swift
//  Habitium
//
//  Free-form daily note attached to a calendar day in PlannerView.
//

import Foundation
import SwiftData

@Model
final class PlannerNote {
    var id: UUID
    var date: Date
    var text: String
    var updatedAt: Date

    init(id: UUID = UUID(), date: Date, text: String, updatedAt: Date = .now) {
        self.id = id
        self.date = date
        self.text = text
        self.updatedAt = updatedAt
    }
}
