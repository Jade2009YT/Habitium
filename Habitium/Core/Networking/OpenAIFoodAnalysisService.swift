//
//  OpenAIFoodAnalysisService.swift
//  Habitium
//
//  Calls the OpenAI Chat Completions API with GPT-4o (vision) to turn a
//  meal photo or description into structured nutrition data. The model is
//  instructed to answer with strict JSON so we can decode it directly —
//  no scraping of prose.
//

import Foundation

final class OpenAIFoodAnalysisService: FoodVisionAnalyzing {

    private let apiKey: String?
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4o"

    init(apiKey: String? = AppConfiguration.openAIAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func analyzeMeal(imageData: Data, additionalContext: String?) async throws -> FoodAnalysisResult {
        let base64Image = imageData.base64EncodedString()
        let userContent: [[String: Any]] = [
            ["type": "text", "text": Self.prompt(additionalContext: additionalContext)],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
        ]
        return try await performRequest(userContent: userContent)
    }

    func analyzeMeal(description: String) async throws -> FoodAnalysisResult {
        let userContent: [[String: Any]] = [
            ["type": "text", "text": Self.prompt(additionalContext: description)]
        ]
        return try await performRequest(userContent: userContent)
    }

    // MARK: - Private

    private func performRequest(userContent: [[String: Any]]) async throws -> FoodAnalysisResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw FoodAnalysisError.missingAPIKey(.openAI)
        }

        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "max_tokens": 500
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8)
        else {
            throw FoodAnalysisError.invalidResponse
        }

        return try Self.decodeAnalysis(from: contentData)
    }

    private static let systemPrompt = """
    Eres un nutricionista experto. Analiza la comida descrita o mostrada en \
    la imagen y responde ÚNICAMENTE con un JSON con este formato exacto: \
    {"mealName": string, "calories": number, "proteinGrams": number, \
    "carbsGrams": number, "fatGrams": number, "confidenceNote": string|null}. \
    Usa estimaciones razonables basadas en porciones estándar.
    """

    private static func prompt(additionalContext: String?) -> String {
        var text = "Analiza esta comida y estima sus calorías y macronutrientes."
        if let additionalContext, !additionalContext.isEmpty {
            text += " Contexto adicional: \(additionalContext)"
        }
        return text
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
