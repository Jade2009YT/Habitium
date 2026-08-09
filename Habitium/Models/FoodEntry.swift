//
//  FoodEntry.swift
//  Habitium
//
//  SwiftData model for a single logged meal, produced either by AI
//  analysis (photo/text) or manual entry.
//

import Foundation
import SwiftData

enum MealSource: String, Codable, CaseIterable {
    case photo
    case text
    case manual
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Desayuno"
        case .lunch: return "Almuerzo"
        case .dinner: return "Cena"
        case .snack: return "Snack"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "carrot.fill"
        }
    }
}

@Model
final class FoodEntry {
    var id: UUID
    var name: String
    var date: Date
    var mealType: MealType.RawValue
    var source: MealSource.RawValue

    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double

    /// Raw photo the user captured, when the entry came from image analysis.
    @Attribute(.externalStorage) var imageData: Data?

    /// Free-form text the user typed (manual description) or the prompt
    /// sent to the AI provider, kept for traceability/debugging.
    var notes: String?

    /// Which AI provider produced this analysis, if any ("openai", "claude").
    var analyzedBy: String?

    init(
        id: UUID = UUID(),
        name: String,
        date: Date = .now,
        mealType: MealType = .breakfast,
        source: MealSource = .manual,
        calories: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        fatGrams: Double = 0,
        imageData: Data? = nil,
        notes: String? = nil,
        analyzedBy: String? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.mealType = mealType.rawValue
        self.source = source.rawValue
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.imageData = imageData
        self.notes = notes
        self.analyzedBy = analyzedBy
    }

    var macros: Macronutrients {
        Macronutrients(proteinGrams: proteinGrams, carbsGrams: carbsGrams, fatGrams: fatGrams)
    }
}

/// Plain value type (not a @Model) shared between the domain layer and AI
/// service responses — keeps macro math out of the persistence type.
struct Macronutrients: Codable, Equatable {
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double

    static let zero = Macronutrients(proteinGrams: 0, carbsGrams: 0, fatGrams: 0)

    /// Calories implied by the macros (protein/carbs = 4 kcal/g, fat = 9 kcal/g),
    /// useful as a sanity check against an AI-reported calorie total.
    var impliedCalories: Double {
        proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
    }
}
