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

    private func normalizedTokenSet(_ text: String) -> Set<String> {
        Set(
            text
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count > 1 }
        )
    }

    private func normalizedText(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func orderedNormalizedTokens(from query: String) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for token in query.components(separatedBy: CharacterSet.alphanumerics.inverted) {
            let normalized = normalizedText(token).trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.count > 1 else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }

    private var genericIntentTerms: Set<String> {
        [
            // === SPANISH ===
            // Interrogatives & common verbs
            "que", "qué", "hice", "hago", "hacer", "hace", "durante", "trabajo", "trabaje", "trabajando",
            "deberia", "debería", "hoy", "ahora", "mi", "mis", "sobre", "acerca", "como", "cuando", "donde", "quien",
            "cuanto", "cuánto", "cuantos", "cuantas", "cuanta", "cuánta",
            "puedo", "puede", "podria", "podría", "quiero", "necesito", "tengo", "tuve",
            // Time
            "tiempo", "dia", "dias", "mes", "meses", "ano", "anos", "semana", "semanas",
            "pasado", "pasada", "anterior", "ultimo", "última", "siguiente", "proximo",
            "ayer", "manana", "mañana",
            // Generic nouns
            "cosa", "cosas", "algo", "nada", "bien", "mal", "mucho", "poco",
            "forma", "manera", "parte", "tipo", "vez", "veces",
            "nombre", "numero", "fecha",
            // Money & payments
            "precio", "pago", "pague", "pagué", "dinero", "total", "cuenta", "coste", "costo",
            "gaste", "gasté", "gasto", "gastos", "factura", "recibo",
            // Utilities & household
            "luz", "agua", "gas", "electricidad", "telefono", "teléfono", "internet", "alquiler",
            // Weather
            "clima", "lluvia", "sol", "temperatura", "grados", "calor", "frio",

            // === ENGLISH ===
            // Interrogatives & common verbs
            "what", "how", "much", "many", "does", "did", "can", "could", "would", "should",
            "need", "want", "know", "think", "tell", "show", "give", "find", "get", "make",
            "like", "look", "help", "work", "worked", "working",
            // Time
            "today", "yesterday", "tomorrow", "last", "next", "previous", "recent",
            "week", "weeks", "month", "months", "year", "years", "day", "days", "time", "ago",
            // Generic nouns
            "thing", "things", "something", "nothing", "good", "bad", "way", "kind", "part",
            "name", "number", "date", "information", "info", "document", "file",
            // Money & payments
            "price", "pay", "paid", "payment", "money", "cost", "total", "bill", "receipt",
            "spend", "spent", "expense", "expenses", "invoice",
            // Utilities & household
            "electricity", "water", "rent", "phone", "internet",
            // Weather
            "weather", "rain", "sunny", "temperature", "degrees", "hot", "cold", "forecast",
            // Other common generic
            "necessary", "important", "possible", "able", "really", "very", "also",
            "still", "just", "some", "any", "every", "each", "best", "most", "more", "less",
            "lose", "weight", "diet", "healthy", "exercise"
        ]
    }

    private func salientQueryTerms(from query: String) -> [String] {
        let ordered = orderedNormalizedTokens(from: query)
        let meaningful = Set(ChunkRepository.meaningfulWords(from: query).map(normalizedText))
        let filtered = ordered.filter { token in
            meaningful.contains(token) && !genericIntentTerms.contains(token)
        }

        if !filtered.isEmpty {
            return filtered
        }

        // Fallback to meaningful words when no salient term survives.
        return ordered.filter { meaningful.contains($0) }
    }

    private func isTemporalQuery(_ query: String) -> Bool {
        let normalized = normalizedText(query)
        let markers = [
            "cuando", "fecha", "desde", "hasta", "periodo", "duracion", "cuanto tiempo",
            "how long", "what year", "inicio", "fin", "entre", "between"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private func temporalEntityTerms(from query: String) -> [String] {
        let temporalTerms: Set<String> = [
            "cuando", "fecha", "desde", "hasta", "periodo", "periodo", "ano", "anos",
            "mes", "meses", "trabaje", "trabajo", "trabajar", "tiempo", "duracion",
            "duration", "when", "worked"
        ]

        let words = salientQueryTerms(from: query)
            .filter { !temporalTerms.contains($0) && !$0.hasPrefix("trabaj") }

        if !words.isEmpty {
            return words
        }

        return query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalizedText)
            .filter { $0.count > 2 && !temporalTerms.contains($0) && !$0.hasPrefix("trabaj") }
    }

    private func datePatternScore(_ text: String) -> Int {
        let normalized = normalizedText(text)
        let patterns = [
            "\\b(19|20)\\d{2}\\b",
            "\\b\\d{1,2}[/-]\\d{4}\\b",
            "\\b\\d{1,2}[/-]\\d{1,2}[/-]\\d{2,4}\\b",
            "\\b(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic|jan|apr|aug|dec)[a-z]*\\s+\\d{4}\\b",
            "\\b(actualidad|presente|current|now)\\b",
            "\\b(19|20)\\d{2}\\s*[-–]\\s*((19|20)\\d{2}|actualidad|presente)\\b"
        ]

        var score = 0
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            score += regex.numberOfMatches(in: normalized, options: [], range: range)
        }
        return score
    }

    private func isNegativeAnswer(_ answer: String) -> Bool {
        let normalized = normalizedText(answer)
        let markers = [
            "no encontre informacion",
            "no se menciona",
            "no aparece",
            "no indica",
            "not mentioned",
            "not provided",
            "i don't have enough information"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private func bestDateLine(in text: String) -> (line: String, score: Int)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 }

        var best: (line: String, score: Int)?
        for line in lines {
            let score = datePatternScore(line)
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                best = (line, score)
            }
        }
        return best
    }

    private func bestEntityLine(in text: String, terms: [String]) -> (line: String, hits: Int)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 }

        var best: (line: String, hits: Int)?
        for line in lines {
            let normalizedLine = normalizedText(line)
            let hits = terms.reduce(into: 0) { partialResult, term in
                if normalizedLine.contains(term) { partialResult += 1 }
            }
            guard hits > 0 else { continue }
            if best == nil || hits > best!.hits {
                best = (line, hits)
            }
        }
        return best
    }

    private func buildTemporalAnswer(from results: [SearchResult], query: String) -> String? {
        guard isTemporalQuery(query), !results.isEmpty else { return nil }

        let entityTerms = temporalEntityTerms(from: query)
        guard !entityTerms.isEmpty else { return nil }
        let entityLabel = entityTerms.first ?? "la entidad"

        let temporalResults = Array(results.prefix(10))
        let entityChunks = temporalResults.compactMap { result -> (result: SearchResult, line: String, hits: Int)? in
            guard let entity = bestEntityLine(in: result.chunkContent, terms: entityTerms) else { return nil }
            return (result, entity.line, entity.hits)
        }
        let dateChunks = temporalResults.compactMap { result -> (result: SearchResult, line: String, score: Int)? in
            guard let date = bestDateLine(in: result.chunkContent) else { return nil }
            return (result, date.line, date.score)
        }

        var bestPair: (doc: String, dateLine: String, entityLine: String, score: Int, distance: Int)?

        for entity in entityChunks {
            for date in dateChunks where date.result.documentId == entity.result.documentId {
                let distance: Int
                if let eIdx = entity.result.chunkIndex, let dIdx = date.result.chunkIndex {
                    distance = abs(eIdx - dIdx)
                } else {
                    distance = 6
                }

                let score = Int(entity.result.score * 100)
                    + Int(date.result.score * 100)
                    + entity.hits * 20
                    + date.score * 30
                    - min(distance, 12) * 8

                if bestPair == nil || score > bestPair!.score {
                    bestPair = (
                        doc: entity.result.documentTitle,
                        dateLine: date.line,
                        entityLine: entity.line,
                        score: score,
                        distance: distance
                    )
                }
            }
        }

        guard let bestPair else { return nil }

        if bestPair.distance > 4 {
            return "En \(bestPair.doc) se menciona \(entityLabel): \(bestPair.entityLine). También aparecen fechas como: \(bestPair.dateLine)."
        }

        if bestPair.dateLine == bestPair.entityLine {
            return "En \(bestPair.doc), para \(entityLabel), aparece: \(bestPair.dateLine)"
        }
        return "En \(bestPair.doc), para \(entityLabel), aparece: \(bestPair.dateLine). Detalle: \(bestPair.entityLine)"
    }

    private func correctedAnswerIfNeeded(answer: String, query: String, context: [SearchResult]) -> String {
        guard !context.isEmpty else { return answer }

        let answerNeedsTemporalFix = isTemporalQuery(query) && datePatternScore(answer) == 0
        let shouldCorrect = isNegativeAnswer(answer) || answerNeedsTemporalFix
        guard shouldCorrect else { return answer }

        let terms = Set(ChunkRepository.meaningfulWords(from: query).map(normalizedText))
        guard !terms.isEmpty else { return answer }

        let contextText = context.map(\.chunkContent).joined(separator: "\n")
        let contextTokens = normalizedTokenSet(contextText)
        let hasTermOverlap = !terms.isDisjoint(with: contextTokens)

        guard hasTermOverlap else { return answer }

        if let temporal = buildTemporalAnswer(from: context, query: query) {
            return temporal
        }

        return buildExtractiveAnswer(from: context, query: query)
    }

    private func expandContextWithNeighbors(
        from selected: [SearchResult],
        query: String,
        limit: Int
    ) async -> [SearchResult] {
        guard !selected.isEmpty else { return [] }

        var merged: [String: SearchResult] = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        var chunkCache: [String: [DocumentChunk]] = [:]

        // Determine how many documents are represented in the selection
        let documentIds = Set(selected.map(\.documentId))

        // For each relevant document, fetch ALL its chunks so the LLM gets
        // the full picture (e.g., all sections of a CV when asking about work at Indra).
        for seed in selected {
            let chunks: [DocumentChunk]
            if let cached = chunkCache[seed.documentId] {
                chunks = cached
            } else {
                guard let fetched = try? await chunkRepo.fetchChunks(forDocumentId: seed.documentId),
                      !fetched.isEmpty else { continue }
                chunkCache[seed.documentId] = fetched
                chunks = fetched
            }

            // If ≤ 2 documents are relevant or the document is small, include ALL chunks.
            // Otherwise use a wider neighbor radius.
            let includeAll = documentIds.count <= 2 || chunks.count <= 8

            if includeAll {
                for chunk in chunks {
                    guard merged[chunk.id] == nil else { continue }
                    // Score neighbors by proximity to the seed
                    let distance: Int
                    if let seedIdx = seed.chunkIndex {
                        distance = abs(chunk.chunkIndex - seedIdx)
                    } else {
                        distance = chunk.chunkIndex
                    }
                    let score = max(seed.score - Float(distance) * 0.03, 0.20)
                    merged[chunk.id] = SearchResult(
                        id: chunk.id,
                        chunkContent: chunk.content,
                        documentId: seed.documentId,
                        documentTitle: seed.documentTitle,
                        score: score,
                        chunkIndex: chunk.chunkIndex
                    )
                }
            } else {
                // Wider radius for multi-document queries
                let neighborRadius = isTemporalQuery(query) ? 3 : 2
                guard let center = chunks.firstIndex(where: { $0.id == seed.id }) else { continue }
                let lower = max(0, center - neighborRadius)
                let upper = min(chunks.count - 1, center + neighborRadius)

                for idx in lower...upper {
                    let neighbor = chunks[idx]
                    guard merged[neighbor.id] == nil else { continue }
                    let distance = abs(idx - center)
                    let score = max(seed.score - Float(distance) * 0.05, 0.30)
                    merged[neighbor.id] = SearchResult(
                        id: neighbor.id,
                        chunkContent: neighbor.content,
                        documentId: seed.documentId,
                        documentTitle: seed.documentTitle,
                        score: score,
                        chunkIndex: neighbor.chunkIndex
                    )
                }
            }
        }

        // Sort by document then by chunk index for coherent reading order
        let sorted = merged.values.sorted { lhs, rhs in
            if lhs.documentId != rhs.documentId {
                // Primary document (highest scoring) comes first
                return lhs.score > rhs.score
            }
            // Within same document, order by chunk index
            return (lhs.chunkIndex ?? 0) < (rhs.chunkIndex ?? 0)
        }

        return Array(sorted.prefix(limit))
    }

    private func selectContextResults(from results: [SearchResult], query: String, limit: Int) -> [SearchResult] {
        guard !results.isEmpty else { return [] }

        let salientTerms = salientQueryTerms(from: query)
        let salientSet = Set(salientTerms)
        let allMeaningful = Set(ChunkRepository.meaningfulWords(from: query).map(normalizedText))

        // Score each result by how many salient/meaningful terms it contains
        let scored: [(result: SearchResult, salientHits: Int, meaningfulHits: Int)] = results.map { result in
            let tokens = normalizedTokenSet(result.chunkContent + " " + result.documentTitle)
            let sHits = salientSet.filter { tokens.contains($0) }.count
            let mHits = allMeaningful.filter { tokens.contains($0) }.count
            return (result, sHits, mHits)
        }

        // Priority 1: results containing salient terms (e.g. "Indra")
        let salientFiltered = scored.filter { $0.salientHits > 0 }
        if !salientFiltered.isEmpty {
            let sorted = salientFiltered.sorted { a, b in
                if a.salientHits != b.salientHits { return a.salientHits > b.salientHits }
                return a.result.score > b.result.score
            }
            return Array(sorted.prefix(limit).map(\.result))
        }

        // Priority 2: results containing ANY meaningful term
        let lexicalFiltered = scored.filter { $0.meaningfulHits > 0 }
        if !lexicalFiltered.isEmpty {
            let sorted = lexicalFiltered.sorted { a, b in
                if a.meaningfulHits != b.meaningfulHits { return a.meaningfulHits > b.meaningfulHits }
                return a.result.score > b.result.score
            }
            return Array(sorted.prefix(limit).map(\.result))
        }

        // Priority 3: results that passed hybridSearch already have a validated score
        // (entity matching and lexical checks are done there) — trust high-scoring results
        let highScoring = results.filter { $0.score >= 0.45 }
        if !highScoring.isEmpty {
            return Array(highScoring.prefix(limit))
        }

        // Nothing relevant found
        return []
    }

    private func search(query: String) async {
        guard let embeddingService = EmbeddingService.shared else {
            await addBotMessage(AppLanguage.current.embeddingsUnavailable)
            return
        }

        do {
            let queryVector = try await embeddingService.generateEmbedding(for: query)

            let results = try await chunkRepo.hybridSearch(
                queryVector: queryVector,
                queryText: query,
                limit: 8,
                minScore: 0.3
            )

            AppLogger.debug("[QA] Query: \"\(query)\"")
            AppLogger.debug("[QA] Salient terms: \(salientQueryTerms(from: query))")
            AppLogger.debug("[QA] Hybrid results: \(results.count)")
            for (i, r) in results.prefix(5).enumerated() {
                AppLogger.debug("[QA]   [\(i)] score=\(String(format: "%.3f", r.score)) doc=\"\(r.documentTitle)\" chunk=\(r.chunkIndex ?? -1) text=\"\(r.chunkContent.prefix(80))...\"")
            }

            if results.isEmpty {
                AppLogger.debug("[QA] ❌ No hybrid results")
                await addBotMessage(AppLanguage.current.noRelevantResults)
                return
            }

            let contextResults = selectContextResults(from: results, query: query, limit: 5)
            AppLogger.debug("[QA] Context selected: \(contextResults.count)")
            guard !contextResults.isEmpty else {
                AppLogger.debug("[QA] ❌ selectContextResults returned empty")
                await addBotMessage(AppLanguage.current.noRelevantResults)
                return
            }

            // Relevance gate: reject queries that don't meaningfully match documents.
            let bestScore = contextResults.map(\.score).max() ?? 0
            let avgScore = contextResults.map(\.score).reduce(0, +) / Float(max(contextResults.count, 1))

            // Check if the query has specific (non-generic) terms.
            // salientQueryTerms filters out genericIntentTerms. If what survives
            // equals the full meaningful set → all terms are specific.
            // If salientQueryTerms returned the fallback → no specific terms.
            let salient = salientQueryTerms(from: query)
            let specificTerms = salient.filter { !genericIntentTerms.contains($0) }
            let hasSpecificTerms = !specificTerms.isEmpty

            // Generic queries ("qué tiempo hace") need much higher score to pass
            let minBest: Float = hasSpecificTerms ? 0.40 : 0.60
            let minAvg: Float = hasSpecificTerms ? 0.35 : 0.55
            AppLogger.debug("[QA] Relevance: best=\(String(format: "%.3f", bestScore)) avg=\(String(format: "%.3f", avgScore)) specific=\(specificTerms) thresholds=(\(minBest),\(minAvg))")

            // Lexical overlap guard: verify the context actually contains words
            // from the query. This prevents vector-only matches where the embedding
            // is "close" but the content is about a completely different topic.
            // This is the MAIN defense against irrelevant answers — not word blocklists.
            do {
                let queryMeaningful = Set(ChunkRepository.meaningfulWords(from: query).map(normalizedText))
                let contextText = contextResults.map(\.chunkContent).joined(separator: " ") + " " + contextResults.map(\.documentTitle).joined(separator: " ")
                let contextTokens = normalizedTokenSet(contextText)
                let specificSet = Set(specificTerms)
                let specificOverlap = specificSet.intersection(contextTokens)
                let meaningfulOverlap = queryMeaningful.intersection(contextTokens)
                AppLogger.debug("[QA] Lexical guard: specific=\(specificSet) found=\(specificOverlap) meaningful=\(queryMeaningful) found=\(meaningfulOverlap)")

                if hasSpecificTerms {
                    // Require MOST specific terms to appear in context.
                    // "adelgazar" query matching only "necesario" in legal text → reject.
                    // "Indra" query matching "Indra" in CV → pass.
                    let required = specificSet.count <= 3 ? specificSet.count : (specificSet.count + 1) / 2
                    if specificOverlap.count < required {
                        AppLogger.debug("[QA] ❌ Only \(specificOverlap.count)/\(specificSet.count) specific terms in context (need \(required)) — rejecting")
                        await addBotMessage(AppLanguage.current.noInfoFound)
                        return
                    }
                } else {
                    // Fully generic query — need strong lexical evidence
                    if meaningfulOverlap.count < 2 {
                        AppLogger.debug("[QA] ❌ Generic query with weak lexical overlap (\(meaningfulOverlap.count)) — rejecting")
                        await addBotMessage(AppLanguage.current.noInfoFound)
                        return
                    }
                }
            }

            if bestScore < minBest || avgScore < minAvg {
                AppLogger.debug("[QA] ❌ Low relevance — rejecting query")
                await addBotMessage(AppLanguage.current.noInfoFound)
                return
            }
            let contextForAnswer = await expandContextWithNeighbors(
                from: contextResults,
                query: query,
                limit: 15
            )
            AppLogger.debug("[QA] Expanded context: \(contextForAnswer.count) chunks")

            var seenCitationKeys = Set<String>()
            let citations = contextResults.compactMap { result -> Citation? in
                let key = "\(result.documentId)|\(result.chunkContent.prefix(100))"
                guard seenCitationKeys.insert(key).inserted else { return nil }
                return Citation(
                    documentId: result.documentId,
                    documentTitle: result.documentTitle,
                    chunkContent: result.chunkContent,
                    score: result.score
                )
            }

            let providerName = qaService.activeProvider?.name ?? "NONE"
            AppLogger.debug("[QA] Provider: \(providerName) available=\(qaService.hasAnyProvider)")

            if qaService.hasAnyProvider {
                var placeholderIndex: Int?
                do {
                    if qaService.canStream {
                        placeholderIndex = messages.count
                        let placeholderMsg = ChatMessage(content: "", isUser: false, citations: citations)
                        messages.append(placeholderMsg)

                        try await qaService.streamAnswer(
                            query: query,
                            context: contextForAnswer
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
                            let finalAnswer = correctedAnswerIfNeeded(
                                answer: messages[placeholderIndex].content,
                                query: query,
                                context: contextForAnswer
                            )
                            if finalAnswer != messages[placeholderIndex].content {
                                messages[placeholderIndex] = ChatMessage(
                                    id: messages[placeholderIndex].id,
                                    content: finalAnswer,
                                    isUser: false,
                                    citations: citations
                                )
                            }
                            await persistBotMessage(messages[placeholderIndex])
                        }
                    } else {
                        let rawAnswer = try await qaService.answer(query: query, context: contextForAnswer)
                        let answer = correctedAnswerIfNeeded(answer: rawAnswer, query: query, context: contextForAnswer)
                        let msg = ChatMessage(content: answer, isUser: false, citations: citations)
                        messages.append(msg)
                        await persistBotMessage(msg)
                    }
                } catch {
                    AppLogger.debug("[QA] ⚠️ LLM failed, using extractive fallback. Error: \(error.localizedDescription)")
                    let answer = buildExtractiveAnswer(from: contextForAnswer, query: query)
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
                AppLogger.debug("[QA] ⚠️ No LLM provider available — using extractive fallback (may be daily limit reached)")
                let answer = buildExtractiveAnswer(from: contextForAnswer, query: query)
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
        if isTemporalQuery(query) {
            if let temporalAnswer = buildTemporalAnswer(from: results, query: query) {
                return temporalAnswer
            }
            return AppLanguage.current.noInfoFound
        }

        let meaningful = ChunkRepository.meaningfulWords(from: query)
        let fallbackWords = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        let baseWords = meaningful.isEmpty ? fallbackWords : meaningful
        let queryWords = Set(
            baseWords.map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
        )

        let queryWordsOriginal = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        let boilerplate = Set(["contacto", "teléfono", "llamar", "sitio web", "www.", "http", "política", "condiciones", "registro", "raee"])

        // Group results by document
        var docGroups: [String: (title: String, results: [SearchResult])] = [:]
        for result in results {
            if var group = docGroups[result.documentId] {
                group.results.append(result)
                docGroups[result.documentId] = group
            } else {
                docGroups[result.documentId] = (result.documentTitle, [result])
            }
        }

        // Score each document
        var docScores: [(docId: String, title: String, score: Int, results: [SearchResult])] = []
        for (docId, group) in docGroups {
            var totalScore = 0
            for result in group.results {
                let chunkTokens = normalizedTokenSet(result.chunkContent)
                for word in queryWords where chunkTokens.contains(word) { totalScore += 5 }
                for word in queryWordsOriginal {
                    if word.first?.isUppercase == true && result.chunkContent.contains(word) { totalScore += 8 }
                }
                totalScore += Int(result.score * 10)
            }
            docScores.append((docId, group.title, totalScore, group.results))
        }

        docScores.sort { $0.score > $1.score }

        guard let bestDoc = docScores.first, bestDoc.score > 0 else {
            return AppLanguage.current.noInfoFound
        }

        // Check minimum relevance
        let allTokens = normalizedTokenSet(bestDoc.results.map(\.chunkContent).joined(separator: " "))
        let matchingQueryWords = queryWords.filter { allTokens.contains($0) }
        if matchingQueryWords.isEmpty && (bestDoc.results.first?.score ?? 0) < 0.5 {
            return AppLanguage.current.noInfoFound
        }

        // Build answer from top documents (include secondary if relevant enough)
        let secondDocScore = docScores.count > 1 ? docScores[1].score : 0
        let docsToInclude = docScores.prefix(secondDocScore > bestDoc.score / 2 ? 2 : 1)

        var documentAnswers: [(title: String, content: String)] = []

        for doc in docsToInclude {
            let content = buildExtractiveContent(
                from: doc.results,
                queryWords: queryWords,
                queryWordsOriginal: queryWordsOriginal,
                boilerplate: boilerplate
            )
            if !content.isEmpty {
                documentAnswers.append((doc.title, content))
            }
        }

        guard !documentAnswers.isEmpty else {
            return AppLanguage.current.noInfoFound
        }

        let fallbackLabel = AppLanguage.current == .spanish ? "tu consulta" : "your query"
        let entityName = queryWordsOriginal.first { $0.first?.isUppercase == true }
            ?? salientQueryTerms(from: query).first
            ?? fallbackLabel

        let lang = AppLanguage.current

        if documentAnswers.count == 1 {
            return "\(lang.extractiveHeader(docTitle: documentAnswers[0].title, entityName: entityName))\n\n\(documentAnswers[0].content)"
        }

        // Multiple documents
        var answer = "\(lang.extractiveMultiHeader(entityName: entityName, count: documentAnswers.count))\n"
        for docAnswer in documentAnswers {
            answer += "\n**\(docAnswer.title)**:\n\(docAnswer.content)\n"
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the most relevant content from a set of search results for one document.
    private func buildExtractiveContent(
        from results: [SearchResult],
        queryWords: Set<String>,
        queryWordsOriginal: [String],
        boilerplate: Set<String>
    ) -> String {
        // Collect all text in chunk order, deduplicating overlapping lines
        let sortedChunks = results.sorted { ($0.chunkIndex ?? 0) < ($1.chunkIndex ?? 0) }

        var seenLines = Set<String>()
        var allLines: [String] = []
        for chunk in sortedChunks {
            let lines = chunk.chunkContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count > 3 }
            for line in lines {
                let key = normalizedText(line)
                if seenLines.insert(key).inserted {
                    allLines.append(line)
                }
            }
        }

        // Score each line for relevance
        struct ScoredLine {
            let text: String
            let index: Int
            let score: Int
        }

        let scoredLines: [ScoredLine] = allLines.enumerated().map { (idx, line) in
            let lineLower = line.lowercased()
            let lineWords = normalizedTokenSet(line)
            var score = queryWords.intersection(lineWords).count * 3

            // Boost proper nouns
            for word in queryWordsOriginal {
                if word.first?.isUppercase == true && line.contains(word) { score += 5 }
            }

            // Lines with colons or key-value patterns are often informative
            if line.contains(":") && line.count > 15 { score += 1 }

            // Penalize boilerplate
            for word in boilerplate where lineLower.contains(word) { score -= 5 }

            return ScoredLine(text: line, index: idx, score: max(score, 0))
        }

        // Group consecutive relevant lines into sections
        // A line is "relevant" if it scores > 0 or is a neighbor of a scoring line
        var sections: [(lines: [String], relevance: Int)] = []
        var currentSection: [String] = []
        var currentRelevance = 0
        var gapCount = 0

        for scored in scoredLines {
            if scored.score > 0 {
                currentSection.append(scored.text)
                currentRelevance += scored.score
                gapCount = 0
            } else if !currentSection.isEmpty {
                gapCount += 1
                if gapCount <= 3 {
                    // Keep context lines between relevant blocks
                    currentSection.append(scored.text)
                } else {
                    sections.append((currentSection, currentRelevance))
                    currentSection = []
                    currentRelevance = 0
                    gapCount = 0
                }
            }
        }

        if !currentSection.isEmpty {
            sections.append((currentSection, currentRelevance))
        }

        // Sort by relevance, take top sections
        sections.sort { $0.relevance > $1.relevance }
        let topSections = sections.prefix(4)

        guard !topSections.isEmpty else { return "" }

        var content = ""
        for (idx, section) in topSections.enumerated() {
            if idx > 0 { content += "\n" }

            let cleanedLines = section.lines.filter { $0.count > 5 }
            if cleanedLines.count <= 3 {
                content += cleanedLines.joined(separator: ". ") + "\n"
            } else {
                for line in cleanedLines {
                    if line.count < 10 && !line.contains(":") { continue }
                    content += "• \(line)\n"
                }
            }
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
