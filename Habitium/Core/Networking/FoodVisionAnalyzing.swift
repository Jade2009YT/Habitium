//
//  FoodVisionAnalyzing.swift
//  Habitium
//
//  Provider-agnostic contract for turning a meal photo or text description
//  into estimated calories + macros. Concrete implementations
//  (OpenAIFoodAnalysisService, ClaudeFoodAnalysisService) live behind this
//  protocol so the ViewModel/UseCase layer never depends on a specific
//  vendor SDK — swapping providers is a DI change, not a rewrite.
//

import Foundation

struct FoodAnalysisResult: Equatable {
    var mealName: String
    var calories: Double
    var macros: Macronutrients
    var confidenceNote: String?
}

enum FoodAnalysisError: LocalizedError {
    case missingAPIKey(AIProviderKind)
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Falta la API key de \(provider.displayName). Configúrala en Configuration/Secrets.xcconfig."
        case .invalidResponse:
            return "El proveedor de IA devolvió una respuesta inesperada."
        case .network(let error):
            return "Error de red: \(error.localizedDescription)"
        }
    }

    static func == (lhs: FoodAnalysisError, rhs: FoodAnalysisError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}

protocol FoodVisionAnalyzing {
    /// Analyzes a meal from a photo (JPEG/PNG data) plus optional free-text
    /// context (e.g. "sin aderezo", "porción grande").
    func analyzeMeal(imageData: Data, additionalContext: String?) async throws -> FoodAnalysisResult

    /// Analyzes a meal purely from a text description, e.g.
    /// "2 huevos revueltos con pan tostado y aguacate".
    func analyzeMeal(description: String) async throws -> FoodAnalysisResult
}
