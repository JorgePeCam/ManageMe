import Foundation
import CloudKit

/// Maps between GRDB models and CKRecords for iCloud Sync.
enum RecordMapper {

    static let zoneName = "ManageMeZone"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName)

    // MARK: - Record Type Names

    enum RecordType {
        static let document = "MM_Document"
        static let folder = "MM_Folder"
        static let conversation = "MM_Conversation"
        static let chatMessage = "MM_ChatMessage"
    }

    // MARK: - Document ↔ CKRecord

    static func recordID(for id: String, recordType: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: zoneID)
    }

    static func record(from doc: Document, existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.document,
            recordID: recordID(for: doc.id, recordType: RecordType.document)
        )

        record["title"] = doc.title as CKRecordValue
        record["content"] = doc.content as CKRecordValue
        record["createdAt"] = doc.createdAt as CKRecordValue
        record["fileType"] = doc.fileType as CKRecordValue
        record["fileSizeBytes"] = (doc.fileSizeBytes ?? 0) as CKRecordValue
        record["sourceType"] = doc.sourceType as CKRecordValue
        record["processingStatus"] = doc.processingStatus as CKRecordValue
        record["errorMessage"] = doc.errorMessage as CKRecordValue?
        record["folderId"] = doc.folderId as CKRecordValue?
        record["modifiedAt"] = (doc.modifiedAt ?? Date()) as CKRecordValue

        // Attach file as CKAsset if available
        if let fileURL = doc.absoluteFileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            record["file"] = CKAsset(fileURL: fileURL)
        }

        return record
    }

    static func document(from record: CKRecord) -> Document? {
        guard record.recordType == RecordType.document else { return nil }

        let id = record.recordID.recordName
        let changeTag = encodeSystemFields(of: record)

        return Document(
            id: id,
            title: record["title"] as? String ?? "Sin título",
            content: record["content"] as? String ?? "",
            createdAt: record["createdAt"] as? Date ?? Date(),
            fileType: FileType(rawValue: record["fileType"] as? String ?? "unknown") ?? .unknown,
            fileURL: nil, // File will be handled separately by SyncFileManager
            fileSizeBytes: record["fileSizeBytes"] as? Int64,
            thumbnailURL: nil,
            sourceType: SourceType(rawValue: record["sourceType"] as? String ?? "files") ?? .files,
            processingStatus: ProcessingStatus(rawValue: record["processingStatus"] as? String ?? "pending") ?? .pending,
            errorMessage: record["errorMessage"] as? String,
            folderId: record["folderId"] as? String,
            syncChangeTag: changeTag,
            needsSyncPush: false,
            modifiedAt: record["modifiedAt"] as? Date ?? Date()
        )
    }

    // MARK: - Folder ↔ CKRecord

    static func record(from folder: Folder, existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.folder,
            recordID: recordID(for: folder.id, recordType: RecordType.folder)
        )

        record["name"] = folder.name as CKRecordValue
        record["parentFolderId"] = folder.parentFolderId as CKRecordValue?
        record["createdAt"] = folder.createdAt as CKRecordValue
        record["modifiedAt"] = (folder.modifiedAt ?? Date()) as CKRecordValue

        return record
    }

    static func folder(from record: CKRecord) -> Folder? {
        guard record.recordType == RecordType.folder else { return nil }

        let id = record.recordID.recordName
        let changeTag = encodeSystemFields(of: record)

        return Folder(
            id: id,
            name: record["name"] as? String ?? "Carpeta",
            parentFolderId: record["parentFolderId"] as? String,
            createdAt: record["createdAt"] as? Date ?? Date(),
            syncChangeTag: changeTag,
            needsSyncPush: false,
            modifiedAt: record["modifiedAt"] as? Date ?? Date()
        )
    }

    // MARK: - Conversation ↔ CKRecord

    static func record(from conv: Conversation, existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.conversation,
            recordID: recordID(for: conv.id, recordType: RecordType.conversation)
        )

        record["title"] = conv.title as CKRecordValue
        record["createdAt"] = conv.createdAt as CKRecordValue
        record["updatedAt"] = conv.updatedAt as CKRecordValue
        record["modifiedAt"] = (conv.modifiedAt ?? Date()) as CKRecordValue

        return record
    }

    static func conversation(from record: CKRecord) -> Conversation? {
        guard record.recordType == RecordType.conversation else { return nil }

        let id = record.recordID.recordName
        let changeTag = encodeSystemFields(of: record)

        return Conversation(
            id: id,
            title: record["title"] as? String ?? "Conversación",
            createdAt: record["createdAt"] as? Date ?? Date(),
            updatedAt: record["updatedAt"] as? Date ?? Date(),
            syncChangeTag: changeTag,
            needsSyncPush: false,
            modifiedAt: record["modifiedAt"] as? Date ?? Date()
        )
    }

    // MARK: - ChatMessage ↔ CKRecord

    static func record(from msg: PersistedChatMessage, existingRecord: CKRecord? = nil) -> CKRecord {
        let record = existingRecord ?? CKRecord(
            recordType: RecordType.chatMessage,
            recordID: recordID(for: msg.id, recordType: RecordType.chatMessage)
        )

        record["conversationId"] = msg.conversationId as CKRecordValue
        record["content"] = msg.content as CKRecordValue
        record["isUser"] = (msg.isUser ? 1 : 0) as CKRecordValue
        record["timestamp"] = msg.timestamp as CKRecordValue
        record["citationsJSON"] = msg.citationsJSON as CKRecordValue?
        record["modifiedAt"] = (msg.modifiedAt ?? Date()) as CKRecordValue

        return record
    }

    static func chatMessage(from record: CKRecord) -> PersistedChatMessage? {
        guard record.recordType == RecordType.chatMessage else { return nil }

        let id = record.recordID.recordName
        let changeTag = encodeSystemFields(of: record)

        var msg = PersistedChatMessage(
            id: id,
            conversationId: record["conversationId"] as? String ?? "",
            content: record["content"] as? String ?? "",
            isUser: (record["isUser"] as? Int64 ?? 0) == 1,
            timestamp: record["timestamp"] as? Date ?? Date(),
            syncChangeTag: changeTag,
            needsSyncPush: false,
            modifiedAt: record["modifiedAt"] as? Date ?? Date()
        )
        msg.citationsJSON = record["citationsJSON"] as? String
        return msg
    }

    // MARK: - System Fields Encoding

    /// Encodes CKRecord system fields (for conflict resolution on next push)
    static func encodeSystemFields(of record: CKRecord) -> String {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData.base64EncodedString()
    }

    /// Decodes a CKRecord from previously saved system fields
    static func decodeRecord(from base64: String) -> CKRecord? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }
}
