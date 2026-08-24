//
//  HabitTemplate.swift
//  Habitium
//
//  Quick-pick presets for AddHabitSheet — lowers the friction of adding a
//  first habit to zero taps of thought. "Tiempo de pantalla" is the one
//  that started this whole module: a manual stand-in for real Screen Time
//  data until (if) the Family Controls entitlement gets approved.
//

import Foundation

struct HabitTemplate: Identifiable {
    var id: String { name }
    var name: String
    var symbolName: String
    var kind: HabitKind
    var targetValue: Double?
    var goalDirection: HabitGoalDirection
    var unit: String?
    /// Pre-checks AddHabitSheet's "marcar automáticamente al entrenar con
    /// el Watch" toggle — only "Ejercicio" makes sense to default on.
    var linkedToWorkouts: Bool = false

    static let all: [HabitTemplate] = [
        HabitTemplate(name: "Tiempo de pantalla", symbolName: "iphone", kind: .numeric, targetValue: 3, goalDirection: .atMost, unit: "h"),
        HabitTemplate(name: "Agua", symbolName: "drop.fill", kind: .numeric, targetValue: 8, goalDirection: .atLeast, unit: "vasos"),
        HabitTemplate(name: "Dormir", symbolName: "bed.double.fill", kind: .numeric, targetValue: 8, goalDirection: .atLeast, unit: "h"),
        HabitTemplate(name: "Ejercicio", symbolName: "figure.run", kind: .checkbox, targetValue: nil, goalDirection: .atLeast, unit: nil, linkedToWorkouts: true),
        HabitTemplate(name: "Leer", symbolName: "book.fill", kind: .checkbox, targetValue: nil, goalDirection: .atLeast, unit: nil),
        HabitTemplate(name: "Meditar", symbolName: "brain.head.profile", kind: .checkbox, targetValue: nil, goalDirection: .atLeast, unit: nil),
        HabitTemplate(name: "Nada de móvil antes de dormir", symbolName: "moon.zzz.fill", kind: .checkbox, targetValue: nil, goalDirection: .atLeast, unit: nil)
    ]
}
