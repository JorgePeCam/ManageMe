import Foundation
import GRDB

struct FolderRepository {
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    func save(_ folder: Folder) async throws {
        var f = folder
        f.needsSyncPush = true
        f.modifiedAt = Date()
        try await db.dbWriter.write { db in
            try f.save(db)
        }
    }

    func update(_ folder: Folder) async throws {
        var f = folder
        f.needsSyncPush = true
        f.modifiedAt = Date()
        try await db.dbWriter.write { db in
            try f.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.dbWriter.write { db in
            if let folder = try Folder.fetchOne(db, key: id) {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO pendingSyncDeletion (recordName, recordType) VALUES (?, ?)",
                    arguments: [folder.id, "MM_Folder"]
                )
            }
            _ = try Folder.deleteOne(db, key: id)
        }
    }

    func fetchAll() async throws -> [Folder] {
        try await db.dbWriter.read { db in
            try Folder
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchRootFolders() async throws -> [Folder] {
        try await db.dbWriter.read { db in
            try Folder
                .filter(Column("parentFolderId") == nil)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchChildren(of folderId: String) async throws -> [Folder] {
        try await db.dbWriter.read { db in
            try Folder
                .filter(Column("parentFolderId") == folderId)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Count documents in a specific folder
    func documentCount(folderId: String) async throws -> Int {
        try await db.dbWriter.read { db in
            try Document
                .filter(Column("folderId") == folderId)
                .fetchCount(db)
        }
    }

    // MARK: - Sync

    func fetchPendingSyncPush() async throws -> [Folder] {
        try await db.dbWriter.read { db in
            try Folder
                .filter(Column("needsSyncPush") == true)
                .fetchAll(db)
        }
    }

    func markSynced(id: String, changeTag: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE folder SET needsSyncPush = 0, syncChangeTag = ? WHERE id = ?",
                arguments: [changeTag, id]
            )
        }
    }

    func saveFromSync(_ folder: Folder) async throws {
        try await db.dbWriter.write { db in
            try folder.save(db)
        }
    }
}
