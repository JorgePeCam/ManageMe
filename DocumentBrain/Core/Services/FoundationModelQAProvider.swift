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

    func answer(query: String, context: [SearchResult], history: [ConversationTurn] = []) async throws -> String {
        #if canImport(FoundationModels)
        do {
            return try await generate(query: query, context: context, history: history, maxChunks: 10, maxChars: 1500)
        } catch {
            do {
                return try await generate(query: query, context: context, history: history, maxChunks: 6, maxChars: 1200)
            } catch {
                return try await generate(query: query, context: context, history: history, maxChunks: 3, maxChars: 800)
            }
        }
        #else
        throw QAError.noProviderAvailable
        #endif
    }

    func streamAnswer(query: String, context: [SearchResult], history: [ConversationTurn] = [], onUpdate: @escaping (String) -> Void) async throws {
        #if canImport(FoundationModels)
        let prompt = buildPrompt(query: query, context: context, history: history, maxChunks: 10, maxChars: 1500)
        let session = LanguageModelSession(instructions: Self.instructions)

        do {
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                onUpdate(partial.content)
            }
        } catch {
            let response = try await session.respond(to: prompt)
            onUpdate(response.content)
        }
        #else
        throw QAError.noProviderAvailable
        #endif
    }

    // MARK: - Private

    #if canImport(FoundationModels)
    private func generate(query: String, context: [SearchResult], history: [ConversationTurn], maxChunks: Int, maxChars: Int) async throws -> String {
        let prompt = buildPrompt(query: query, context: context, history: history, maxChunks: maxChunks, maxChars: maxChars)
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    private static var instructions: String { AppLanguage.current.systemPrompt }

    private func buildPrompt(query: String, context: [SearchResult], history: [ConversationTurn], maxChunks: Int, maxChars: Int) -> String {
        let lang = AppLanguage.current
        var prompt = ""

        if !history.isEmpty {
            let historyLabel = lang == .spanish ? "CONVERSACIÓN PREVIA" : "PREVIOUS CONVERSATION"
            prompt += "\(historyLabel):\n"
            for turn in history {
                let userLabel = lang == .spanish ? "Usuario" : "User"
                let assistantLabel = lang == .spanish ? "Asistente" : "Assistant"
                prompt += "\(userLabel): \(turn.userMessage)\n"
                prompt += "\(assistantLabel): \(turn.assistantMessage)\n\n"
            }
        }

        let chunks = context.prefix(maxChunks)
        prompt += "\(lang.snippetsHeader)\n\n"
        for (idx, result) in chunks.enumerated() {
            let text = String(result.chunkContent.prefix(maxChars))
            prompt += "\(lang.snippetLabel(title: result.documentTitle, index: idx + 1))\n\(text)\n\n"
        }
        prompt += "\(lang.questionLabel): \(query)"
        return prompt
    }
}
