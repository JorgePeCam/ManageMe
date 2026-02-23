import Foundation
import GRDB

struct DocumentChunk: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "documentChunk"

    var id: String
    var documentId: String
    var content: String
    var chunkIndex: Int
    var startOffset: Int?
    var endOffset: Int?

    init(
        id: String = UUID().uuidString,
        documentId: String,
        content: String,
        chunkIndex: Int,
        startOffset: Int? = nil,
        endOffset: Int? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.chunkIndex = chunkIndex
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

struct ChunkVector: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chunkVector"

    var chunkId: String
    var embedding: Data

    init(chunkId: String, embedding: [Float]) {
        self.chunkId = chunkId
        self.embedding = embedding.toData()
    }

    var embeddingArray: [Float] {
        embedding.toFloatArray()
    }
}

struct SearchResult: Identifiable {
    var id: String
    var chunkContent: String
    var documentId: String
    var documentTitle: String
    var score: Float
    var chunkIndex: Int? = nil
}
