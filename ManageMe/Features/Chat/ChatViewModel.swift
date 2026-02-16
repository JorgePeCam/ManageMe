import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var queryText = ""
    @Published var isSearching = false
    @Published var streamingText = ""

    // Conversation history
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let chunkRepo = ChunkRepository()
    private let qaService = QAService.shared
    private let conversationRepo = ConversationRepository()
    private var cancellables = Set<AnyCancellable>()

    init() {
        Task { await loadConversations() }

        NotificationCenter.default.publisher(for: .allDataDidDelete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAllDataDeleted()
            }
            .store(in: &cancellables)
    }

    private func handleAllDataDeleted() {
        conversations = []
        currentConversation = nil
        messages = []
        queryText = ""
        streamingText = ""
        isSearching = false
    }

    // MARK: - Conversation Management

    func loadConversations() async {
        do {
            conversations = try await conversationRepo.fetchAll()
        } catch {
            conversations = []
        }
    }

    func startNewConversation() {
        currentConversation = nil
        messages = []
        queryText = ""
        streamingText = ""
    }

    func loadConversation(_ conversation: Conversation) async {
        currentConversation = conversation
        do {
            let persisted = try await conversationRepo.fetchMessages(for: conversation.id)
            messages = persisted.map { ChatMessage(from: $0) }
        } catch {
            messages = []
        }
    }

    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await conversationRepo.delete(conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if currentConversation?.id == conversation.id {
                startNewConversation()
            }
        } catch { }
    }

    func deleteAllConversations() async {
        do {
            try await conversationRepo.deleteAllConversations()
            conversations = []
            startNewConversation()
        } catch { }
    }

    // MARK: - Messaging

    func sendQuery() {
        let query = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        messages.append(ChatMessage(content: query, isUser: true))
        queryText = ""
        isSearching = true
        streamingText = ""

        Task {
            // Ensure we have a conversation
            if currentConversation == nil {
                let title = generateTitle(from: query)
                let conv = Conversation(title: title)
                try? await conversationRepo.save(conv)
                currentConversation = conv
                conversations.insert(conv, at: 0)
            }

            // Persist user message
            if let convId = currentConversation?.id, let lastUserMsg = messages.last(where: { $0.isUser }) {
                let persisted = PersistedChatMessage(
                    id: lastUserMsg.id,
                    conversationId: convId,
                    content: lastUserMsg.content,
                    isUser: true
                )
                try? await conversationRepo.saveMessage(persisted)
            }

            await search(query: query)

            // Update conversation timestamp
            if let convId = currentConversation?.id {
                try? await conversationRepo.touchUpdatedAt(convId)
                await loadConversations()
            }
        }
    }

    func clearMessages() {
        startNewConversation()
    }

    // MARK: - Search & QA

    private func search(query: String) async {
        guard let embeddingService = EmbeddingService.shared else {
            await addBotMessage("El modelo de embeddings no está disponible. Asegúrate de que MiniLM está incluido en el proyecto.")
            return
        }

        do {
            let queryVector = try await embeddingService.generateEmbedding(for: query)

            let results = try await chunkRepo.hybridSearch(
                queryVector: queryVector,
                queryText: query,
                limit: 5,
                minScore: 0.3
            )

            // Check that results are truly relevant (top score must be above threshold)
            if results.isEmpty || results[0].score < 0.35 {
                await addBotMessage("No encontré información relevante en tus documentos. Prueba con otra pregunta o importa más archivos.")
                return
            }

            let citations = results.prefix(3).map { result in
                Citation(
                    documentId: result.documentId,
                    documentTitle: result.documentTitle,
                    chunkContent: result.chunkContent,
                    score: result.score
                )
            }

            if qaService.hasAnyProvider {
                var placeholderIndex: Int?
                do {
                    if qaService.canStream {
                        placeholderIndex = messages.count
                        let placeholderMsg = ChatMessage(content: "", isUser: false, citations: citations)
                        messages.append(placeholderMsg)

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
                                        id: placeholderMsg.id,
                                        content: partialText,
                                        isUser: false,
                                        citations: citations
                                    )
                                }
                            }
                        }
                        streamingText = ""

                        // Persist final streamed message
                        if let placeholderIndex, placeholderIndex < messages.count {
                            await persistBotMessage(messages[placeholderIndex])
                        }
                    } else {
                        let answer = try await qaService.answer(query: query, context: Array(results.prefix(3)))
                        let msg = ChatMessage(content: answer, isUser: false, citations: citations)
                        messages.append(msg)
                        await persistBotMessage(msg)
                    }
                } catch {
                    let answer = buildExtractiveAnswer(from: results, query: query)
                    if let placeholderIndex,
                       placeholderIndex < messages.count {
                        let msg = ChatMessage(
                            id: messages[placeholderIndex].id,
                            content: answer,
                            isUser: false,
                            citations: citations
                        )
                        messages[placeholderIndex] = msg
                        await persistBotMessage(msg)
                    } else {
                        let msg = ChatMessage(content: answer, isUser: false, citations: citations)
                        messages.append(msg)
                        await persistBotMessage(msg)
                    }
                }
            } else {
                let answer = buildExtractiveAnswer(from: results, query: query)
                let msg = ChatMessage(content: answer, isUser: false, citations: citations)
                messages.append(msg)
                await persistBotMessage(msg)
            }

        } catch {
            await addBotMessage("Error: \(error.localizedDescription)")
        }

        isSearching = false
    }

    private func addBotMessage(_ text: String) async {
        let msg = ChatMessage(content: text, isUser: false)
        messages.append(msg)
        isSearching = false
        await persistBotMessage(msg)
    }

    private func persistBotMessage(_ msg: ChatMessage) async {
        guard let convId = currentConversation?.id else { return }
        let persisted = PersistedChatMessage(
            id: msg.id,
            conversationId: convId,
            content: msg.content,
            isUser: false,
            citations: msg.citations
        )
        try? await conversationRepo.saveMessage(persisted)
    }

    // MARK: - Title Generation

    private func generateTitle(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 40 {
            return trimmed
        }
        let truncated = String(trimmed.prefix(37))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }

    // MARK: - Extractive Fallback

    private func buildExtractiveAnswer(from results: [SearchResult], query: String = "") -> String {
        let queryWords = Set(
            query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )

        // Also keep original cased words for proper noun matching (e.g. "Indra")
        let queryWordsOriginal = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        let dataPatterns: [String] = [
            "\\d{1,2}[:/]\\d{2}",
            "\\d{1,2}\\s+(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)",
            "\\d{4}",
            "[A-Z]{3}\\s*[→➡\\-–]",
            "[→➡\\-–]\\s*[A-Z]{3}",
            "\\d+\\.\\d{2}\\s*(€|\\$|USD|EUR)",
            "^[A-Z]{2,3}\\d{2,4}",
        ]

        let boilerplate = ["contacto", "teléfono", "llamar", "sitio web", "www.", "http", "política", "condiciones", "registro", "raee"]

        // Score each result as a whole to pick the BEST document
        var bestResultIndex = 0
        var bestResultScore = 0

        for (idx, result) in results.prefix(3).enumerated() {
            let chunkLower = result.chunkContent.lowercased()
            var totalScore = 0

            // Count query words that appear in the chunk
            for word in queryWords {
                if chunkLower.contains(word) {
                    totalScore += 5
                }
            }

            // Bonus for proper nouns found verbatim
            for word in queryWordsOriginal {
                if word.first?.isUppercase == true && result.chunkContent.contains(word) {
                    totalScore += 8
                }
            }

            // Boost by search score
            totalScore += Int(result.score * 10)

            if totalScore > bestResultScore {
                bestResultScore = totalScore
                bestResultIndex = idx
            }
        }

        // Check if the best result actually has query word matches
        // If no query words match at all, the results are likely irrelevant
        let bestResult = results[bestResultIndex]
        let bestChunkLower = bestResult.chunkContent.lowercased()
        let matchingQueryWords = queryWords.filter { bestChunkLower.contains($0) }

        if matchingQueryWords.isEmpty && bestResult.score < 0.5 {
            return "No encontré información específica sobre tu consulta en los documentos."
        }

        let lines = bestResult.chunkContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 3 }

        var scoredLines: [(line: String, score: Int)] = []

        for line in lines {
            var score = 0
            let lineLower = line.lowercased()

            let lineWords = Set(
                lineLower
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count > 2 }
            )
            score += queryWords.intersection(lineWords).count * 3

            // Bonus for proper noun exact match in line
            for word in queryWordsOriginal {
                if word.first?.isUppercase == true && line.contains(word) {
                    score += 5
                }
            }

            for pattern in dataPatterns {
                if line.range(of: pattern, options: .regularExpression, range: nil, locale: nil) != nil {
                    score += 2
                }
            }

            if line.count > 120 { score -= 2 }

            for word in boilerplate {
                if lineLower.contains(word) { score -= 3 }
            }

            if score > 0 {
                scoredLines.append((line, score))
            }
        }

        // Also include context lines around high-scoring lines
        let topLines = scoredLines
            .sorted { $0.score > $1.score }
            .prefix(8)

        if topLines.isEmpty {
            return "No encontré información específica sobre tu consulta en los documentos."
        }

        let header = "De **\(bestResult.documentTitle)**:"
        let content = topLines.map { $0.line }.joined(separator: "\n")
        return "\(header)\n\n\(content)"
    }
}
