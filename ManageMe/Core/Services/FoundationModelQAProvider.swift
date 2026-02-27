import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Q&A provider using Apple Foundation Models (iOS 26+, on-device)
/// Runs entirely on-device — free, private, no API key needed
@available(iOS 26, macOS 26, *)
final class FoundationModelQAProvider: StreamableQAProvider {
    var name: String { "Apple Intelligence (on-device)" }
    var kind: QAProviderKind { .onDevice }

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.availability == .available
        #else
        return false
        #endif
    }

    func answer(query: String, context: [SearchResult]) async throws -> String {
        #if canImport(FoundationModels)
        // Try with richer context first, then progressively reduce if needed.
        do {
            return try await generate(query: query, context: context, maxChunks: 10, maxChars: 1500)
        } catch {
            do {
                return try await generate(query: query, context: context, maxChunks: 6, maxChars: 1200)
            } catch {
                return try await generate(query: query, context: context, maxChunks: 3, maxChars: 800)
            }
        }
        #else
        throw QAError.noProviderAvailable
        #endif
    }

    func streamAnswer(query: String, context: [SearchResult], onUpdate: @escaping (String) -> Void) async throws {
        #if canImport(FoundationModels)
        let prompt = buildPrompt(query: query, context: context, maxChunks: 10, maxChars: 1500)
        let session = LanguageModelSession(instructions: Self.instructions)

        do {
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                onUpdate(partial.content)
            }
        } catch {
            // Streaming failed — try non-streaming as fallback
            let response = try await session.respond(to: prompt)
            onUpdate(response.content)
        }
        #else
        throw QAError.noProviderAvailable
        #endif
    }

    // MARK: - Private

    #if canImport(FoundationModels)
    private func generate(query: String, context: [SearchResult], maxChunks: Int, maxChars: Int) async throws -> String {
        let prompt = buildPrompt(query: query, context: context, maxChunks: maxChunks, maxChars: maxChars)
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    /// Uses the shared AppLanguage system prompt for consistency with Gemini
    private static var instructions: String {
        AppLanguage.current.systemPrompt
    }

    private func buildPrompt(query: String, context: [SearchResult], maxChunks: Int, maxChars: Int) -> String {
        let lang = AppLanguage.current
        let chunks = context.prefix(maxChunks)
        var prompt = "\(lang.snippetsHeader)\n\n"
        for (idx, result) in chunks.enumerated() {
            let text = String(result.chunkContent.prefix(maxChars))
            prompt += "\(lang.snippetLabel(title: result.documentTitle, index: idx + 1))\n\(text)\n\n"
        }
        prompt += "\(lang.questionLabel): \(query)"
        return prompt
    }
}
