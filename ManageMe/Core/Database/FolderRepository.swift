import Foundation
import GRDB

struct FolderRepository {
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    func save(_ folder: Folder) async throws {
        try await db.dbWriter.write { db in
            try folder.save(db)
        }
    }

    func update(_ folder: Folder) async throws {
        try await db.dbWriter.write { db in
            try folder.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.dbWriter.write { db in
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
}
