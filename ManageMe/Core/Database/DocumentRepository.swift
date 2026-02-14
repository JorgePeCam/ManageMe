import Foundation
import GRDB

struct DocumentRepository {
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    // MARK: - CRUD

    func save(_ document: Document) async throws {
        try await db.dbWriter.write { db in
            try document.save(db)
        }
    }

    func update(_ document: Document) async throws {
        try await db.dbWriter.write { db in
            try document.update(db)
        }
    }

    func delete(id: String) async throws {
        try await db.dbWriter.write { db in
            _ = try Document.deleteOne(db, key: id)
        }
    }

    func fetchAll() async throws -> [Document] {
        try await db.dbWriter.read { db in
            try Document
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchOne(id: String) async throws -> Document? {
        try await db.dbWriter.read { db in
            try Document.fetchOne(db, key: id)
        }
    }

    func fetchByStatus(_ status: ProcessingStatus) async throws -> [Document] {
        try await db.dbWriter.read { db in
            try Document
                .filter(Column("processingStatus") == status.rawValue)
                .fetchAll(db)
        }
    }

    func updateStatus(id: String, status: ProcessingStatus, error: String? = nil) async throws {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE document SET processingStatus = ?, errorMessage = ? WHERE id = ?",
                arguments: [status.rawValue, error, id]
            )
        }
    }

    func updateContent(id: String, content: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE document SET content = ? WHERE id = ?",
                arguments: [content, id]
            )
        }
    }

    // MARK: - Folder Queries

    /// Fetch documents in a specific folder (nil = root level)
    func fetchByFolder(_ folderId: String?) async throws -> [Document] {
        try await db.dbWriter.read { db in
            if let folderId {
                return try Document
                    .filter(Column("folderId") == folderId)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            } else {
                return try Document
                    .filter(Column("folderId") == nil)
                    .order(Column("createdAt").desc)
                    .fetchAll(db)
            }
        }
    }

    /// Move a document to a folder (nil = root)
    func moveToFolder(documentId: String, folderId: String?) async throws {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE document SET folderId = ? WHERE id = ?",
                arguments: [folderId, documentId]
            )
        }
    }

    // MARK: - File Management

    /// Creates the directories for storing document files and thumbnails
    static func ensureStorageDirectories() throws {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        let filesDir = documentsDir.appendingPathComponent("files")
        let thumbsDir = documentsDir.appendingPathComponent("thumbnails")

        if !fileManager.fileExists(atPath: filesDir.path) {
            try fileManager.createDirectory(at: filesDir, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: thumbsDir.path) {
            try fileManager.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        }
    }

    /// Copies a file into the app's storage and returns the relative path
    func importFile(from sourceURL: URL, fileType: FileType) throws -> (relativePath: String, fileSize: Int64) {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        let fileName = "\(UUID().uuidString).\(sourceURL.pathExtension)"
        let relativePath = "files/\(fileName)"
        let destinationURL = documentsDir.appendingPathComponent(relativePath)

        // Start accessing security-scoped resource if needed
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? Int64) ?? 0

        return (relativePath, fileSize)
    }

    /// Deletes the file associated with a document
    func deleteFile(for document: Document) {
        guard let fileURL = document.absoluteFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)

        if let thumbURL = document.absoluteThumbnailURL {
            try? FileManager.default.removeItem(at: thumbURL)
        }
    }
}
