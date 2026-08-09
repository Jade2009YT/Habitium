//
//  FoodAnalysisServiceFactory.swift
//  Habitium
//
//  Resolves the FoodVisionAnalyzing implementation to use based on the
//  user's preferred provider (UserSettings.preferredAIProvider).
//

import Foundation

enum FoodAnalysisServiceFactory {
    static func make(for provider: AIProviderKind) -> FoodVisionAnalyzing {
        switch provider {
        case .openAI:
            return OpenAIFoodAnalysisService()
        case .claude:
            return ClaudeFoodAnalysisService()
        }
    }
}
