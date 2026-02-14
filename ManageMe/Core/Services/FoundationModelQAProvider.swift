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
        // Try with full context first, retry with less if it fails
        do {
            return try await generate(query: query, context: context, maxChunks: 2, maxChars: 300)
        } catch {
            // Retry with minimal context
            do {
                return try await generate(query: query, context: context, maxChunks: 1, maxChars: 200)
            } catch {
                throw error
            }
        }
        #else
        throw QAError.noProviderAvailable
        #endif
    }

    func streamAnswer(query: String, context: [SearchResult], onUpdate: @escaping (String) -> Void) async throws {
        #if canImport(FoundationModels)
        let prompt = buildPrompt(query: query, context: context, maxChunks: 2, maxChars: 300)
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

    private static let instructions = "Answer concisely using only the provided text. Same language as the question."

    private func buildPrompt(query: String, context: [SearchResult], maxChunks: Int, maxChars: Int) -> String {
        let chunks = context.prefix(maxChunks)
        var prompt = ""
        for result in chunks {
            let text = String(result.chunkContent.prefix(maxChars))
            prompt += "\(text)\n\n"
        }
        prompt += "Q: \(query)"
        return prompt
    }
}
