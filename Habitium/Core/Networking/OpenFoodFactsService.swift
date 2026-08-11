//
//  OpenFoodFactsService.swift
//  Habitium
//
//  Barcode → nutrition lookup via Open Food Facts (openfoodfacts.org), a
//  free, keyless, crowd-sourced product database — the same kind of
//  lookup MyFitnessPal/Fooducate's barcode scanner uses under the hood.
//  No API key, no Secrets.xcconfig entry needed.
//

import Foundation

enum BarcodeLookupError: LocalizedError {
    case notFound
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "No se encontró ningún producto con ese código de barras en Open Food Facts."
        case .invalidResponse: return "Open Food Facts devolvió una respuesta inesperada."
        case .network(let error): return "Error de red: \(error.localizedDescription)"
        }
    }
}

protocol BarcodeLookupService {
    /// Looks up nutrition facts *per 100 g/ml* for the given barcode. The
    /// caller (AddMealView) asks the user for an actual portion size and
    /// scales these numbers — Open Food Facts doesn't know your serving.
    func lookupProduct(barcode: String) async throws -> FoodAnalysisResult
}

final class OpenFoodFactsService: BarcodeLookupService {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookupProduct(barcode: String) async throws -> FoodAnalysisResult {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,nutriments") else {
            throw BarcodeLookupError.invalidResponse
        }

        let data: Data
        do {
            let (responseData, _) = try await session.data(from: url)
            data = responseData
        } catch {
            throw BarcodeLookupError.network(error)
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["status"] as? Int) == 1,
            let product = root["product"] as? [String: Any]
        else {
            throw BarcodeLookupError.notFound
        }

        let name = (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Producto escaneado"
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        func value(_ key: String) -> Double {
            (nutriments[key] as? Double) ?? (nutriments[key] as? Int).map(Double.init) ?? 0
        }

        return FoodAnalysisResult(
            mealName: name,
            calories: value("energy-kcal_100g"),
            macros: Macronutrients(
                proteinGrams: value("proteins_100g"),
                carbsGrams: value("carbohydrates_100g"),
                fatGrams: value("fat_100g")
            ),
            confidenceNote: "Valores por 100 g (Open Food Facts) — ajusta según tu porción real."
        )
    }
}
