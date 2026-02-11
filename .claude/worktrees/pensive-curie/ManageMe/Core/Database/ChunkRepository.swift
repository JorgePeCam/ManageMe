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
        try await db.dbWriter.read { db in
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
            """, arguments: [query, limit])

            return rows.map { row in
                SearchResult(
                    id: row["id"],
                    chunkContent: row["content"],
                    documentId: row["documentId"],
                    documentTitle: row["title"],
                    score: 1.0 // FTS uses rank, normalize later
                )
            }
        }
    }

    // MARK: - Hybrid Search

    func hybridSearch(
        queryVector: [Float],
        queryText: String,
        limit: Int = 5,
        minScore: Float = 0.2
    ) async throws -> [SearchResult] {
        // Get vector results
        let vectorResults = try await searchByVector(
            queryVector: queryVector,
            limit: limit * 2,
            minScore: minScore
        )

        // Get keyword results
        let ftsResults = try await searchByKeywords(query: queryText, limit: limit * 2)

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

        // Calculate final scores: 0.6 * semantic + 0.4 * keyword bonus
        var merged: [SearchResult] = scoreMap.values.map { entry in
            let semanticScore = entry.vectorScore
            let keywordBonus: Float = entry.ftsHit ? 0.4 : 0.0
            let finalScore = 0.6 * semanticScore + keywordBonus

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
