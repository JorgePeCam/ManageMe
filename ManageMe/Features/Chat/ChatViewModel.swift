import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var queryText = ""
    @Published var isSearching = false

    private let chunkRepo = ChunkRepository()
    private let qaService = QAService.shared

    func sendQuery() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        messages.append(ChatMessage(content: query, isUser: true))
        queryText = ""
        isSearching = true

        Task {
            await search(query: query)
        }
    }

    func clearMessages() {
        messages = []
    }

    private func search(query: String) async {
        guard let embeddingService = EmbeddingService.shared else {
            addBotMessage("El modelo de embeddings no está disponible. Asegúrate de que MiniLM está incluido en el proyecto.")
            return
        }

        do {
            // 1. Search for relevant chunks
            let queryVector = try await embeddingService.generateEmbedding(for: query)

            let results = try await chunkRepo.hybridSearch(
                queryVector: queryVector,
                queryText: query,
                limit: 5,
                minScore: 0.15
            )

            if results.isEmpty {
                addBotMessage("No encontré información relevante en tus documentos. Prueba con otra pregunta o importa más archivos.")
                return
            }

            // 2. Build citations from search results
            let citations = results.prefix(3).map { result in
                Citation(
                    documentId: result.documentId,
                    documentTitle: result.documentTitle,
                    chunkContent: result.chunkContent,
                    score: result.score
                )
            }

            // 3. Generate answer with LLM if available, otherwise extractive
            let answer: String
            if qaService.hasAnyProvider {
                answer = try await qaService.answer(query: query, context: Array(results.prefix(5)))
            } else {
                answer = buildExtractiveAnswer(from: results, query: query)
            }

            messages.append(ChatMessage(
                content: answer,
                isUser: false,
                citations: citations
            ))

        } catch {
            addBotMessage("Error: \(error.localizedDescription)")
        }

        isSearching = false
    }

    private func addBotMessage(_ text: String) {
        messages.append(ChatMessage(content: text, isUser: false))
        isSearching = false
    }

    /// Fallback when no LLM is available: shows relevant text directly
    private func buildExtractiveAnswer(from results: [SearchResult], query: String) -> String {
        let topResults = Array(results.prefix(3))

        var answer = "⚠️ Configura tu API key en Ajustes para respuestas inteligentes.\n\nFragmentos encontrados:\n\n"
        for (index, result) in topResults.enumerated() {
            if index > 0 { answer += "\n\n---\n\n" }
            let lines = result.chunkContent
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(6)
                .joined(separator: "\n")
            answer += "📄 \(result.documentTitle):\n\(lines)"
        }

        return answer
    }
}
