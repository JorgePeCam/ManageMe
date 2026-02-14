import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var queryText = ""
    @Published var isSearching = false
    @Published var streamingText = ""

    private let chunkRepo = ChunkRepository()
    private let qaService = QAService.shared

    func sendQuery() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        messages.append(ChatMessage(content: query, isUser: true))
        queryText = ""
        isSearching = true
        streamingText = ""

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

            // 3. Generate answer
            if qaService.hasAnyProvider {
                var placeholderIndex: Int?
                do {
                    if qaService.canStream {
                        // Streaming: update message in real-time
                        placeholderIndex = messages.count
                        messages.append(ChatMessage(content: "", isUser: false, citations: citations))

                        try await qaService.streamAnswer(
                            query: query,
                            context: Array(results.prefix(3))
                        ) { [weak self] partialText in
                            Task { @MainActor in
                                guard let self else { return }
                                self.streamingText = partialText
                                if let placeholderIndex,
                                   placeholderIndex < self.messages.count {
                                    self.messages[placeholderIndex] = ChatMessage(
                                        content: partialText,
                                        isUser: false,
                                        citations: citations
                                    )
                                }
                            }
                        }
                        streamingText = ""
                    } else {
                        let answer = try await qaService.answer(query: query, context: Array(results.prefix(3)))
                        messages.append(ChatMessage(content: answer, isUser: false, citations: citations))
                    }
                } catch {
                    // AI failed — fallback to extractive answer
                    let answer = buildExtractiveAnswer(from: results, query: query)
                    if let placeholderIndex,
                       placeholderIndex < messages.count {
                        messages[placeholderIndex] = ChatMessage(
                            content: answer,
                            isUser: false,
                            citations: citations
                        )
                    } else {
                        messages.append(ChatMessage(content: answer, isUser: false, citations: citations))
                    }
                }
            } else {
                let answer = buildExtractiveAnswer(from: results, query: query)
                messages.append(ChatMessage(content: answer, isUser: false, citations: citations))
            }

        } catch {
            addBotMessage("Error: \(error.localizedDescription)")
        }

        isSearching = false
    }

    private func addBotMessage(_ text: String) {
        messages.append(ChatMessage(content: text, isUser: false))
        isSearching = false
    }

    /// Fallback: extracts the most relevant lines from chunks matching the query
    private func buildExtractiveAnswer(from results: [SearchResult], query: String = "") -> String {
        let queryWords = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )

        // Patterns that indicate concrete/useful data (dates, times, codes, numbers)
        let dataPatterns: [String] = [
            "\\d{1,2}[:/]\\d{2}",           // times like 17:15 or 8:30
            "\\d{1,2}\\s+(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)",  // dates
            "\\d{4}",                         // years like 2026
            "[A-Z]{3}\\s*[→➡\\-–]",         // airport codes like SGN →
            "[→➡\\-–]\\s*[A-Z]{3}",         // → BKK
            "\\d+\\.\\d{2}\\s*(€|\\$|USD|EUR)", // prices
            "^[A-Z]{2,3}\\d{2,4}",           // flight numbers like VJ123
        ]

        var scoredLines: [(line: String, score: Int)] = []

        for result in results.prefix(3) {
            let lines = result.chunkContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count > 3 }

            for line in lines {
                var score = 0

                // Query word overlap
                let lineWords = Set(
                    line.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count > 2 }
                )
                score += queryWords.intersection(lineWords).count * 2

                // Bonus for concrete data patterns
                for pattern in dataPatterns {
                    if line.range(of: pattern, options: .regularExpression, range: nil, locale: nil) != nil {
                        score += 3
                    }
                }

                // Penalize very long generic text lines
                if line.count > 120 { score -= 2 }

                // Penalize lines that look like boilerplate
                let boilerplate = ["contacto", "teléfono", "llamar", "sitio web", "www.", "http", "política", "condiciones"]
                for word in boilerplate {
                    if line.lowercased().contains(word) { score -= 3 }
                }

                if score > 0 {
                    scoredLines.append((line, score))
                }
            }
        }

        // Sort by relevance, take top lines
        let topLines = scoredLines
            .sorted { $0.score > $1.score }
            .prefix(6)

        if topLines.isEmpty {
            // Ultra-fallback: just show the first few meaningful lines from best result
            if let best = results.first {
                let lines = best.chunkContent
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0.count > 3 && $0.count < 100 }
                    .prefix(4)
                    .joined(separator: "\n")
                return lines.isEmpty ? "No encontré información específica." : lines
            }
            return "No encontré información específica sobre tu consulta."
        }

        return topLines
            .map { $0.line }
            .joined(separator: "\n")
    }
}
