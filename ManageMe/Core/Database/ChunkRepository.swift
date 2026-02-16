import Foundation
import GRDB

struct ChunkRepository {
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    // MARK: - Chunks

    func saveChunk(_ chunk: DocumentChunk, embedding: [Float]) async throws {
        try await db.dbWriter.write { db in
            try chunk.save(db)
            let vector = ChunkVector(chunkId: chunk.id, embedding: embedding)
            try vector.save(db)
        }
    }

    func saveChunks(_ chunks: [(chunk: DocumentChunk, embedding: [Float])]) async throws {
        try await db.dbWriter.write { db in
            for item in chunks {
                try item.chunk.save(db)
                let vector = ChunkVector(chunkId: item.chunk.id, embedding: item.embedding)
                try vector.save(db)
            }
        }
    }

    func deleteChunks(forDocumentId documentId: String) async throws {
        try await db.dbWriter.write { db in
            try DocumentChunk
                .filter(Column("documentId") == documentId)
                .deleteAll(db)
        }
    }

    func fetchChunks(forDocumentId documentId: String) async throws -> [DocumentChunk] {
        try await db.dbWriter.read { db in
            try DocumentChunk
                .filter(Column("documentId") == documentId)
                .order(Column("chunkIndex"))
                .fetchAll(db)
        }
    }

    // MARK: - Vector Search

    func searchByVector(queryVector: [Float], limit: Int = 5, minScore: Float = 0.25) async throws -> [SearchResult] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id, c.content, c.documentId, d.title, v.embedding
                FROM documentChunk c
                JOIN chunkVector v ON c.id = v.chunkId
                JOIN document d ON c.documentId = d.id
                WHERE d.processingStatus = 'ready'
            """)

            var results: [SearchResult] = []
            for row in rows {
                let vectorData: Data = row["embedding"]
                let vector = vectorData.toFloatArray()
                let score = VectorMath.cosineSimilarity(queryVector, vector)

                if score >= minScore {
                    results.append(SearchResult(
                        id: row["id"],
                        chunkContent: row["content"],
                        documentId: row["documentId"],
                        documentTitle: row["title"],
                        score: score
                    ))
                }
            }

            return results
                .sorted { $0.score > $1.score }
                .prefix(limit)
                .map { $0 }
        }
    }

    // MARK: - FTS Search

    func searchByKeywords(query: String, limit: Int = 5) async throws -> [SearchResult] {
        // Sanitize query for FTS5: remove special characters, keep only words
        let sanitized = Self.sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        return try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.id, c.content, c.documentId, d.title,
                       rank AS ftsScore
                FROM documentChunk_fts fts
                JOIN documentChunk c ON c.rowid = fts.rowid
                JOIN document d ON c.documentId = d.id
                WHERE documentChunk_fts MATCH ?
                AND d.processingStatus = 'ready'
                ORDER BY rank
                LIMIT ?
            """, arguments: [sanitized, limit])

            return rows.map { row in
                SearchResult(
                    id: row["id"],
                    chunkContent: row["content"],
                    documentId: row["documentId"],
                    documentTitle: row["title"],
                    score: 1.0
                )
            }
        }
    }

    /// Spanish + English stopwords to exclude from keyword searches
    private static let stopwords: Set<String> = [
        // Spanish
        "que", "qué", "de", "del", "la", "el", "en", "es", "lo", "los", "las",
        "un", "una", "uno", "por", "con", "para", "al", "se", "su", "sus",
        "mi", "mis", "tu", "tus", "nos", "les", "como", "pero", "mas", "más",
        "ya", "este", "esta", "ese", "esa", "hay", "fue", "son", "ser", "sin",
        "sobre", "entre", "cuando", "muy", "puede", "donde", "tiene", "sido",
        "desde", "está", "están", "era", "han", "todo", "otra", "otro",
        "cual", "cuál", "aquí", "también", "cada", "nos", "porque",
        // English
        "the", "is", "at", "which", "on", "and", "or", "in", "to", "of",
        "for", "with", "was", "are", "has", "have", "had", "not", "but",
        "from", "this", "that", "these", "those", "what", "when", "where",
        "how", "who", "why", "my", "your", "his", "her", "its", "our"
    ]

    /// Converts user text into a valid FTS5 query.
    /// Removes punctuation, stopwords, and joins meaningful words with OR.
    static func sanitizeFTSQuery(_ query: String) -> String {
        let words = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 1 }
            .filter { !stopwords.contains($0.lowercased()) }

        guard !words.isEmpty else { return "" }

        // Wrap each word in quotes to avoid FTS5 syntax issues, join with OR
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    /// Returns meaningful words from a query (excluding stopwords)
    static func meaningfulWords(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
            .filter { !stopwords.contains($0.lowercased()) }
    }

    // MARK: - Hybrid Search

    func hybridSearch(
        queryVector: [Float],
        queryText: String,
        limit: Int = 5,
        minScore: Float = 0.3
    ) async throws -> [SearchResult] {
        // Get vector results
        let vectorResults = try await searchByVector(
            queryVector: queryVector,
            limit: limit * 2,
            minScore: 0.2
        )

        // Get keyword results (already uses stopword-filtered query)
        let ftsResults = try await searchByKeywords(query: queryText, limit: limit * 2)

        // Extract meaningful query words (no stopwords)
        let meaningfulWords = Self.meaningfulWords(from: queryText)
        let meaningfulWordsLower = Set(meaningfulWords.map { $0.lowercased() })

        // Merge: combine scores for chunks that appear in both
        var scoreMap: [String: (result: SearchResult, vectorScore: Float, ftsHit: Bool)] = [:]

        for result in vectorResults {
            scoreMap[result.id] = (result, result.score, false)
        }

        for result in ftsResults {
            if var existing = scoreMap[result.id] {
                existing.ftsHit = true
                scoreMap[result.id] = existing
            } else {
                scoreMap[result.id] = (result, 0, true)
            }
        }

        // Calculate final scores with meaningful keyword content matching
        var merged: [SearchResult] = scoreMap.values.compactMap { entry in
            let semanticScore = entry.vectorScore
            let chunkLower = entry.result.chunkContent.lowercased()

            // Count how many MEANINGFUL query words appear in the chunk
            let matchingMeaningful = meaningfulWordsLower.filter { chunkLower.contains($0) }
            let meaningfulRatio = meaningfulWordsLower.isEmpty
                ? 0.0
                : Float(matchingMeaningful.count) / Float(meaningfulWordsLower.count)

            // FTS bonus only if meaningful words actually match in the content
            let keywordBonus: Float
            if entry.ftsHit && !matchingMeaningful.isEmpty {
                keywordBonus = 0.15 + meaningfulRatio * 0.25 // 0.15–0.40 depending on word match ratio
            } else {
                keywordBonus = 0.0
            }

            // Direct content match bonus for each meaningful word found
            let contentBonus: Float = min(Float(matchingMeaningful.count) * 0.1, 0.3)

            let finalScore = 0.6 * semanticScore + keywordBonus + contentBonus

            // Filter out truly irrelevant results
            guard finalScore >= minScore else { return nil }

            return SearchResult(
                id: entry.result.id,
                chunkContent: entry.result.chunkContent,
                documentId: entry.result.documentId,
                documentTitle: entry.result.documentTitle,
                score: finalScore
            )
        }

        merged.sort { $0.score > $1.score }
        return Array(merged.prefix(limit))
    }
}
