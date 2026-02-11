import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var queryText = ""
    @Published var isSearching = false

    private let chunkRepo = ChunkRepository()

    func sendQuery() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // Add user message
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
            messages.append(ChatMessage(
                content: "El modelo de IA no esta disponible. Asegurate de que el modelo MiniLM esta incluido en el proyecto.",
                isUser: false
            ))
            isSearching = false
            return
        }

        do {
            let queryVector = try await embeddingService.generateEmbedding(for: query)

            let results = try await chunkRepo.hybridSearch(
                queryVector: queryVector,
                queryText: query,
                limit: 5,
                minScore: 0.15
            )

            if results.isEmpty {
                messages.append(ChatMessage(
                    content: "No encontre informacion relevante en tus documentos sobre eso. Prueba con otra pregunta o importa mas archivos.",
                    isUser: false
                ))
            } else {
                // Build extractive answer from top results
                let answer = buildAnswer(from: results, query: query)
                let citations = results.prefix(3).map { result in
                    Citation(
                        documentId: result.documentId,
                        documentTitle: result.documentTitle,
                        chunkContent: result.chunkContent,
                        score: result.score
                    )
                }

                messages.append(ChatMessage(
                    content: answer,
                    isUser: false,
                    citations: citations
                ))
            }
        } catch {
            messages.append(ChatMessage(
                content: "Error al buscar: \(error.localizedDescription)",
                isUser: false
            ))
        }

        isSearching = false
    }

    /// Builds an extractive answer by selecting the most relevant passages
    private func buildAnswer(from results: [SearchResult], query: String) -> String {
        if results.count == 1 {
            return results[0].chunkContent
        }

        // Show top passages separated clearly
        var answer = ""
        for (index, result) in results.prefix(3).enumerated() {
            if index > 0 { answer += "\n\n---\n\n" }
            answer += "De \"\(result.documentTitle)\":\n\(result.chunkContent)"
        }

        return answer
    }
}
