import Foundation

/// Q&A provider using Apple Foundation Models (iOS 26+, on-device)
/// Falls back gracefully on unsupported devices
@available(iOS 26, *)
final class FoundationModelQAProvider: QAProvider {
    var name: String { "Apple Intelligence (on-device)" }

    var isAvailable: Bool {
        // Check if Foundation Models framework is available and the model is ready
        // This will only be true on iPhone 15 Pro+, M1+ iPad, with iOS 26+
        guard let modelClass = NSClassFromString("FoundationModels.SystemLanguageModel") else {
            return false
        }
        // Check availability via the framework
        return checkModelAvailability()
    }

    func answer(query: String, context: [SearchResult]) async throws -> String {
        // Dynamic loading to avoid compile errors on iOS < 26
        let prompt = QAService.buildPrompt(query: query, context: context)
        return try await generateWithFoundationModels(prompt: prompt)
    }

    private func checkModelAvailability() -> Bool {
        // Will be implemented when building with iOS 26 SDK
        // For now, return false to use OpenAI fallback
        return false
    }

    private func generateWithFoundationModels(prompt: String) async throws -> String {
        // Placeholder: will use FoundationModels.SystemLanguageModel when iOS 26 SDK is available
        // Example future implementation:
        //
        // import FoundationModels
        // let model = SystemLanguageModel.default
        // guard model.availability == .available else { throw QAError.noProviderAvailable }
        // let session = LanguageModelSession()
        // let response = try await session.respond(to: prompt)
        // return response.content
        //
        throw QAError.noProviderAvailable
    }
}
