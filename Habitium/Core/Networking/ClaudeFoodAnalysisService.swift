//
//  ClaudeFoodAnalysisService.swift
//  Habitium
//
//  Alternative AI provider using Anthropic's Messages API (Claude, vision
//  capable) to analyze a meal photo or description. Same contract as
//  OpenAIFoodAnalysisService so FoodTrackerViewModel can switch providers
//  via UserSettings.preferredAIProvider without any other code changes.
//

import Foundation

final class ClaudeFoodAnalysisService: FoodVisionAnalyzing {

    private let apiKey: String?
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-5"
    private let apiVersion = "2023-06-01"

    init(apiKey: String? = AppConfiguration.anthropicAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func analyzeMeal(imageData: Data, additionalContext: String?) async throws -> FoodAnalysisResult {
        let base64Image = imageData.base64EncodedString()
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": base64Image]
            ],
            ["type": "text", "text": Self.prompt(additionalContext: additionalContext)]
        ]
        return try await performRequest(content: content)
    }

    func analyzeMeal(description: String) async throws -> FoodAnalysisResult {
        let content: [[String: Any]] = [
            ["type": "text", "text": Self.prompt(additionalContext: description)]
        ]
        return try await performRequest(content: content)
    }

    // MARK: - Private

    private func performRequest(content: [[String: Any]]) async throws -> FoodAnalysisResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw FoodAnalysisError.missingAPIKey(.claude)
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            let (responseData, _) = try await session.data(for: request)
            data = responseData
        } catch {
            throw FoodAnalysisError.network(error)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let contentBlocks = root["content"] as? [[String: Any]],
            let text = contentBlocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
            let textData = Self.extractJSON(from: text)?.data(using: .utf8)
        else {
            throw FoodAnalysisError.invalidResponse
        }

        return try Self.decodeAnalysis(from: textData)
    }

    private static let systemPrompt = """
    Eres un nutricionista experto. Analiza la comida descrita o mostrada en \
    la imagen y responde ÚNICAMENTE con un JSON con este formato exacto, sin \
    texto adicional: {"mealName": string, "calories": number, \
    "proteinGrams": number, "carbsGrams": number, "fatGrams": number, \
    "confidenceNote": string|null}. Usa estimaciones razonables basadas en \
    porciones estándar.
    """

    private static func prompt(additionalContext: String?) -> String {
        var text = "Analiza esta comida y estima sus calorías y macronutrientes."
        if let additionalContext, !additionalContext.isEmpty {
            text += " Contexto adicional: \(additionalContext)"
        }
        return text
    }

    /// Claude sometimes wraps JSON in prose despite instructions; grab the
    /// outermost {...} block defensively.
    private static func extractJSON(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        return String(text[start...end])
    }

    private static func decodeAnalysis(from data: Data) throws -> FoodAnalysisResult {
        struct RawResult: Decodable {
            let mealName: String
            let calories: Double
            let proteinGrams: Double
            let carbsGrams: Double
            let fatGrams: Double
            let confidenceNote: String?
        }
        guard let raw = try? JSONDecoder().decode(RawResult.self, from: data) else {
            throw FoodAnalysisError.invalidResponse
        }
        return FoodAnalysisResult(
            mealName: raw.mealName,
            calories: raw.calories,
            macros: Macronutrients(proteinGrams: raw.proteinGrams, carbsGrams: raw.carbsGrams, fatGrams: raw.fatGrams),
            confidenceNote: raw.confidenceNote
        )
    }
}
