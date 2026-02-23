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

    private static let instructions = """
    You are a document QA assistant. You answer questions based ONLY on the provided document snippets.

    RULES:
    1. ONLY use facts that are EXPLICITLY written in the snippets.
    2. If NONE of the snippets contain relevant information, reply EXACTLY: "No encontré información sobre esto en tus documentos."
    3. NEVER invent or guess information not in the snippets.
    4. NEVER use general knowledge — only cite what is written.
    5. If a snippet is about a different topic than the question, IGNORE it.
    6. Respond in the same language as the question.

    RESPONSE STYLE:
    - Give DETAILED, thorough answers. Include all relevant data you find: dates, names, technologies, responsibilities, amounts, locations, etc.
    - If information is spread across multiple snippets from the same document, synthesize it into one coherent, complete answer.
    - Use paragraphs, bullet points, or sections to organize the information clearly.
    - Do NOT give one-line answers when the snippets contain more detail. Elaborate fully.
    - Cite the document name when relevant.
    """

    private func buildPrompt(query: String, context: [SearchResult], maxChunks: Int, maxChars: Int) -> String {
        let chunks = context.prefix(maxChunks)
        var prompt = "FRAGMENTOS DE DOCUMENTOS DEL USUARIO:\n\n"
        for (idx, result) in chunks.enumerated() {
            let text = String(result.chunkContent.prefix(maxChars))
            prompt += "[\(idx + 1)] Documento: \"\(result.documentTitle)\"\n\(text)\n\n"
        }
        prompt += """
        PREGUNTA DEL USUARIO: \(query)

        INSTRUCCIONES: Responde con DETALLE usando toda la información relevante de los fragmentos. Si hay datos distribuidos en varios fragmentos del mismo documento, sintetízalos en una respuesta completa. Si los fragmentos NO contienen información relevante, responde "No encontré información sobre esto en tus documentos."

        RESPUESTA:
        """
        return prompt
    }
}
