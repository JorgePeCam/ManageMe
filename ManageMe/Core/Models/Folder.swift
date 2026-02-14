import Foundation
import GRDB

struct Folder: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder"

    var id: String
    var name: String
    var parentFolderId: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        parentFolderId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentFolderId = parentFolderId
        self.createdAt = createdAt
    }
}
