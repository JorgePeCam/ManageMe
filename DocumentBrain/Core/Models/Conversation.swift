import Foundation
import GRDB

// MARK: - Conversation

struct Conversation: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversation"

    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    // Sync metadata
    var syncChangeTag: String?
    var needsSyncPush: Bool
    var modifiedAt: Date?

    init(
        id: String = UUID().uuidString,
        title: String = "Nueva conversación",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncChangeTag: String? = nil,
        needsSyncPush: Bool = true,
        modifiedAt: Date? = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncChangeTag = syncChangeTag
        self.needsSyncPush = needsSyncPush
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Persisted Chat Message

struct PersistedChatMessage: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chatMessage"

    var id: String
    var conversationId: String
    var content: String
    var isUser: Bool
    var timestamp: Date
    var citationsJSON: String?

    // Sync metadata
    var syncChangeTag: String?
    var needsSyncPush: Bool
    var modifiedAt: Date?

    init(
        id: String = UUID().uuidString,
        conversationId: String,
        content: String,
        isUser: Bool,
        timestamp: Date = Date(),
        citations: [Citation] = [],
        syncChangeTag: String? = nil,
        needsSyncPush: Bool = true,
        modifiedAt: Date? = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.citationsJSON = citations.isEmpty ? nil : Self.encodeCitations(citations)
        self.syncChangeTag = syncChangeTag
        self.needsSyncPush = needsSyncPush
        self.modifiedAt = modifiedAt
    }

    var citations: [Citation] {
        guard let json = citationsJSON else { return [] }
        return Self.decodeCitations(json)
    }

    private static func encodeCitations(_ citations: [Citation]) -> String? {
        guard let data = try? JSONEncoder().encode(citations) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeCitations(_ json: String) -> [Citation] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Citation].self, from: data)) ?? []
    }
}

// MARK: - In-Memory Chat Message (for UI)

struct ChatMessage: Identifiable {
    let id: String
    let content: String
    let isUser: Bool
    let timestamp: Date
    let citations: [Citation]
    let debugInfo: RAGDebugInfo?

    init(id: String = UUID().uuidString, content: String, isUser: Bool, citations: [Citation] = [], debugInfo: RAGDebugInfo? = nil) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.citations = citations
        self.debugInfo = debugInfo
    }

    init(from persisted: PersistedChatMessage) {
        self.id = persisted.id
        self.content = persisted.content
        self.isUser = persisted.isUser
        self.timestamp = persisted.timestamp
        self.citations = persisted.citations
        self.debugInfo = nil
    }
}

// MARK: - RAG Debug Info

struct RAGDebugInfo {
    let originalQuery: String
    let expandedQuery: String
    let provider: String
    let results: [RAGDebugResult]
}

struct RAGDebugResult: Identifiable {
    let id = UUID()
    let documentTitle: String
    let chunkIndex: Int?
    let score: Float
    let preview: String
}

// MARK: - Citation

struct Citation: Identifiable, Codable {
    let id: String
    let documentId: String
    let documentTitle: String
    let chunkContent: String
    let score: Float

    init(
        id: String = UUID().uuidString,
        documentId: String,
        documentTitle: String,
        chunkContent: String,
        score: Float
    ) {
        self.id = id
        self.documentId = documentId
        self.documentTitle = documentTitle
        self.chunkContent = chunkContent
        self.score = score
    }
}
