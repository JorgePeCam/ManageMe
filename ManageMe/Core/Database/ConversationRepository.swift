import Foundation
import GRDB

struct ConversationRepository {
    private var dbWriter: any DatabaseWriter { AppDatabase.shared.dbWriter }

    // MARK: - Conversations

    func fetchAll() async throws -> [Conversation] {
        try await dbWriter.read { db in
            try Conversation
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func save(_ conversation: Conversation) async throws {
        var c = conversation
        c.needsSyncPush = true
        c.modifiedAt = Date()
        try await dbWriter.write { db in
            try c.save(db)
        }
    }

    func delete(_ conversationId: String) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO pendingSyncDeletion (recordName, recordType) VALUES (?, ?)",
                arguments: [conversationId, "MM_Conversation"]
            )
            _ = try Conversation.deleteOne(db, id: conversationId)
        }
    }

    func updateTitle(_ conversationId: String, title: String) async throws {
        try await dbWriter.write { db in
            if var conversation = try Conversation.fetchOne(db, id: conversationId) {
                conversation.title = title
                conversation.updatedAt = Date()
                try conversation.update(db)
            }
        }
    }

    func touchUpdatedAt(_ conversationId: String) async throws {
        try await dbWriter.write { db in
            if var conversation = try Conversation.fetchOne(db, id: conversationId) {
                conversation.updatedAt = Date()
                try conversation.update(db)
            }
        }
    }

    // MARK: - Messages

    func fetchMessages(for conversationId: String) async throws -> [PersistedChatMessage] {
        try await dbWriter.read { db in
            try PersistedChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("timestamp").asc)
                .fetchAll(db)
        }
    }

    func saveMessage(_ message: PersistedChatMessage) async throws {
        var m = message
        m.needsSyncPush = true
        m.modifiedAt = Date()
        try await dbWriter.write { db in
            try m.save(db)
        }
    }

    func updateMessageContent(_ messageId: String, content: String) async throws {
        try await dbWriter.write { db in
            if var msg = try PersistedChatMessage.fetchOne(db, id: messageId) {
                msg.content = content
                try msg.update(db)
            }
        }
    }

    func messageCount(for conversationId: String) async throws -> Int {
        try await dbWriter.read { db in
            try PersistedChatMessage
                .filter(Column("conversationId") == conversationId)
                .fetchCount(db)
        }
    }

    func deleteAllConversations() async throws {
        try await dbWriter.write { db in
            _ = try Conversation.deleteAll(db)
        }
    }

    // MARK: - Sync

    func fetchPendingSyncPushConversations() async throws -> [Conversation] {
        try await dbWriter.read { db in
            try Conversation
                .filter(Column("needsSyncPush") == true)
                .fetchAll(db)
        }
    }

    func fetchPendingSyncPushMessages() async throws -> [PersistedChatMessage] {
        try await dbWriter.read { db in
            try PersistedChatMessage
                .filter(Column("needsSyncPush") == true)
                .fetchAll(db)
        }
    }

    func markConversationSynced(id: String, changeTag: String) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE conversation SET needsSyncPush = 0, syncChangeTag = ? WHERE id = ?",
                arguments: [changeTag, id]
            )
        }
    }

    func markMessageSynced(id: String, changeTag: String) async throws {
        try await dbWriter.write { db in
            try db.execute(
                sql: "UPDATE chatMessage SET needsSyncPush = 0, syncChangeTag = ? WHERE id = ?",
                arguments: [changeTag, id]
            )
        }
    }

    func saveConversationFromSync(_ conversation: Conversation) async throws {
        try await dbWriter.write { db in
            try conversation.save(db)
        }
    }

    func saveMessageFromSync(_ message: PersistedChatMessage) async throws {
        try await dbWriter.write { db in
            try message.save(db)
        }
    }
}
