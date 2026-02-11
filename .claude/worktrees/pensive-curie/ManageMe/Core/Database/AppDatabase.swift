import Foundation
import GRDB

final class AppDatabase {
    static let shared = makeShared()

    let dbWriter: any DatabaseWriter

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private static func makeShared() -> AppDatabase {
        do {
            let fileManager = FileManager.default
            let folderURL = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = folderURL.appendingPathComponent("manageme.sqlite")
            let dbPool = try DatabasePool(path: dbURL.path)
            return try AppDatabase(dbWriter: dbPool)
        } catch {
            fatalError("Error iniciando base de datos: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createDocuments") { db in
            try db.create(table: "document") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("fileType", .text).notNull().defaults(to: "unknown")
                t.column("fileURL", .text)
                t.column("fileSizeBytes", .integer)
                t.column("thumbnailURL", .text)
                t.column("sourceType", .text).notNull().defaults(to: "files")
                t.column("processingStatus", .text).notNull().defaults(to: "pending")
                t.column("errorMessage", .text)
            }

            try db.create(table: "documentChunk") { t in
                t.column("id", .text).primaryKey()
                t.column("documentId", .text).notNull()
                    .references("document", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
                t.column("startOffset", .integer)
                t.column("endOffset", .integer)
            }

            try db.create(table: "chunkVector") { t in
                t.column("chunkId", .text).primaryKey()
                    .references("documentChunk", onDelete: .cascade)
                t.column("embedding", .blob).notNull()
            }

            // FTS5 para busqueda por keywords
            try db.execute(sql: """
                CREATE VIRTUAL TABLE documentChunk_fts USING fts5(
                    content,
                    content=documentChunk,
                    content_rowid=rowid
                )
            """)

            // Triggers para mantener FTS sincronizado
            try db.execute(sql: """
                CREATE TRIGGER documentChunk_ai AFTER INSERT ON documentChunk BEGIN
                    INSERT INTO documentChunk_fts(rowid, content)
                    VALUES (new.rowid, new.content);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER documentChunk_ad AFTER DELETE ON documentChunk BEGIN
                    INSERT INTO documentChunk_fts(documentChunk_fts, rowid, content)
                    VALUES ('delete', old.rowid, old.content);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER documentChunk_au AFTER UPDATE ON documentChunk BEGIN
                    INSERT INTO documentChunk_fts(documentChunk_fts, rowid, content)
                    VALUES ('delete', old.rowid, old.content);
                    INSERT INTO documentChunk_fts(rowid, content)
                    VALUES (new.rowid, new.content);
                END
            """)
        }

        return migrator
    }
}
