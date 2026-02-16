import Foundation
import CloudKit
import Combine
import GRDB

/// Orchestrates bidirectional iCloud sync using CKSyncEngine.
/// Local GRDB is the source of truth; CKSyncEngine handles scheduling,
/// retry, deduplication, and batching.
@available(iOS 17.0, *)
final class SyncCoordinator: NSObject, ObservableObject {

    static let shared = SyncCoordinator()

    // MARK: - Published state

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var iCloudAvailable = false

    // MARK: - Dependencies

    private var syncEngine: CKSyncEngine?
    private let container = CKContainer(identifier: "iCloud.Jorge-Perez-Campos.ManageMe")
    private let documentRepo = DocumentRepository()
    private let folderRepo = FolderRepository()
    private let conversationRepo = ConversationRepository()
    private let db = AppDatabase.shared

    // MARK: - Lifecycle

    func start() {
        Task {
            await checkAccountStatus()
            guard iCloudAvailable else { return }
            await initializeSyncEngine()
        }
    }

    func stop() {
        syncEngine = nil
    }

    // MARK: - Account

    private func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                iCloudAvailable = (status == .available)
                if !iCloudAvailable {
                    syncError = "iCloud no disponible. Inicia sesión en Ajustes > iCloud."
                }
            }
        } catch {
            await MainActor.run {
                iCloudAvailable = false
                syncError = "Error verificando iCloud: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Engine Initialization

    private func initializeSyncEngine() async {
        // Load persisted CKSyncEngine.State if available
        let savedState = await loadSyncEngineState()

        let config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: savedState,
            delegate: self
        )

        let engine = CKSyncEngine(config)
        self.syncEngine = engine

        // Schedule any pending changes
        await schedulePendingChanges()
    }

    // MARK: - Schedule Pending Changes

    func schedulePendingChanges() async {
        guard let engine = syncEngine else { return }

        do {
            // Documents
            let docs = try await documentRepo.fetchPendingSyncPush()
            for doc in docs {
                let id = RecordMapper.recordID(for: doc.id, recordType: RecordMapper.RecordType.document)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }

            // Folders
            let folders = try await folderRepo.fetchPendingSyncPush()
            for folder in folders {
                let id = RecordMapper.recordID(for: folder.id, recordType: RecordMapper.RecordType.folder)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }

            // Conversations
            let convs = try await conversationRepo.fetchPendingSyncPushConversations()
            for conv in convs {
                let id = RecordMapper.recordID(for: conv.id, recordType: RecordMapper.RecordType.conversation)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }

            // Chat messages
            let msgs = try await conversationRepo.fetchPendingSyncPushMessages()
            for msg in msgs {
                let id = RecordMapper.recordID(for: msg.id, recordType: RecordMapper.RecordType.chatMessage)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }

            // Pending deletions
            let deletions = try await fetchPendingDeletions()
            for deletion in deletions {
                let id = CKRecord.ID(recordName: deletion.recordName, zoneID: RecordMapper.zoneID)
                engine.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
            }
        } catch {
            print("SyncCoordinator: Error scheduling pending changes — \(error)")
        }
    }

    // MARK: - Persistence

    private func loadSyncEngineState() async -> CKSyncEngine.State.Serialization? {
        do {
            return try await db.dbWriter.read { db in
                guard let row = try Row.fetchOne(db, sql: "SELECT data FROM syncState WHERE key = 'engineState'"),
                      let data = row["data"] as? Data else {
                    return nil
                }
                return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
            }
        } catch {
            print("SyncCoordinator: Error loading sync state — \(error)")
            return nil
        }
    }

    private func saveSyncEngineState(_ state: CKSyncEngine.State.Serialization) {
        Task {
            do {
                let data = try JSONEncoder().encode(state)
                try await db.dbWriter.write { db in
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO syncState (key, data) VALUES ('engineState', ?)",
                        arguments: [data]
                    )
                }
            } catch {
                print("SyncCoordinator: Error saving sync state — \(error)")
            }
        }
    }

    // MARK: - Pending Deletions

    private struct PendingDeletion: FetchableRecord, Decodable {
        let recordName: String
        let recordType: String
    }

    private func fetchPendingDeletions() async throws -> [PendingDeletion] {
        try await db.dbWriter.read { db in
            try PendingDeletion.fetchAll(db, sql: "SELECT * FROM pendingSyncDeletion")
        }
    }

    private func removePendingDeletion(recordName: String) async {
        do {
            try await db.dbWriter.write { db in
                try db.execute(
                    sql: "DELETE FROM pendingSyncDeletion WHERE recordName = ?",
                    arguments: [recordName]
                )
            }
        } catch {
            print("SyncCoordinator: Error removing pending deletion — \(error)")
        }
    }
}

// MARK: - CKSyncEngineDelegate

@available(iOS 17.0, *)
extension SyncCoordinator: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let stateUpdate):
            saveSyncEngineState(stateUpdate.stateSerialization)

        case .accountChange(let accountChange):
            handleAccountChange(accountChange)

        case .fetchedDatabaseChanges(let fetchedChanges):
            // Zone creations/deletions — for now, just log
            if !fetchedChanges.modifications.isEmpty {
                print("SyncCoordinator: Fetched \(fetchedChanges.modifications.count) zone modifications")
            }

        case .fetchedRecordZoneChanges(let fetchedChanges):
            handleFetchedRecordZoneChanges(fetchedChanges)

        case .sentRecordZoneChanges(let sentChanges):
            handleSentRecordZoneChanges(sentChanges)

        case .sentDatabaseChanges:
            break

        case .willFetchChanges:
            Task { @MainActor in isSyncing = true }

        case .willFetchRecordZoneChanges:
            break

        case .didFetchRecordZoneChanges:
            break

        case .didFetchChanges:
            Task { @MainActor in
                isSyncing = false
                lastSyncDate = Date()
                syncError = nil
            }

        case .willSendChanges:
            Task { @MainActor in isSyncing = true }

        case .didSendChanges:
            Task { @MainActor in
                isSyncing = false
                lastSyncDate = Date()
            }

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = syncEngine.state.pendingRecordZoneChanges

        // Pre-build all records synchronously to avoid async in the closure
        let recordMap = buildRecordMap(for: pendingChanges)

        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { recordID in
            return recordMap[recordID]
        }

        return batch
    }

    // MARK: - Build Record for Push

    /// Pre-loads all pending records into a dictionary for synchronous access.
    private func buildRecordMap(for changes: [CKSyncEngine.PendingRecordZoneChange]) -> [CKRecord.ID: CKRecord] {
        var map: [CKRecord.ID: CKRecord] = [:]

        // Collect IDs that need saving (not deletions)
        let saveIDs: [(CKRecord.ID, String)] = changes.compactMap { change in
            if case .saveRecord(let recordID) = change {
                return (recordID, recordID.recordName)
            }
            return nil
        }

        guard !saveIDs.isEmpty else { return map }

        do {
            try db.dbWriter.read { db in
                for (recordID, id) in saveIDs {
                    if let doc = try Document.fetchOne(db, key: id) {
                        let existing = doc.syncChangeTag.flatMap { RecordMapper.decodeRecord(from: $0) }
                        map[recordID] = RecordMapper.record(from: doc, existingRecord: existing)
                    } else if let folder = try Folder.fetchOne(db, key: id) {
                        let existing = folder.syncChangeTag.flatMap { RecordMapper.decodeRecord(from: $0) }
                        map[recordID] = RecordMapper.record(from: folder, existingRecord: existing)
                    } else if let conv = try Conversation.fetchOne(db, key: id) {
                        let existing = conv.syncChangeTag.flatMap { RecordMapper.decodeRecord(from: $0) }
                        map[recordID] = RecordMapper.record(from: conv, existingRecord: existing)
                    } else if let msg = try PersistedChatMessage.fetchOne(db, key: id) {
                        let existing = msg.syncChangeTag.flatMap { RecordMapper.decodeRecord(from: $0) }
                        map[recordID] = RecordMapper.record(from: msg, existingRecord: existing)
                    }
                }
            }
        } catch {
            print("SyncCoordinator: Error building record map — \(error)")
        }

        return map
    }

    // MARK: - Handle Fetched Changes (Incoming)

    private func handleFetchedRecordZoneChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        Task {
            // Process modifications
            for modification in changes.modifications {
                let record = modification.record
                await applyIncomingRecord(record)
            }

            // Process deletions
            for deletion in changes.deletions {
                await applyIncomingDeletion(recordID: deletion.recordID)
            }
        }
    }

    private func applyIncomingRecord(_ record: CKRecord) async {
        do {
            switch record.recordType {
            case RecordMapper.RecordType.document:
                guard var doc = RecordMapper.document(from: record) else { return }

                // Handle file asset download
                if let asset = record["file"] as? CKAsset {
                    let fileType = FileType(rawValue: doc.fileType) ?? .unknown
                    let relativePath = await SyncFileManager.shared.importAsset(from: record, fileType: fileType)
                    doc.fileURL = relativePath

                    // Update file size
                    if let relativePath, let url = doc.absoluteFileURL {
                        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                        doc.fileSizeBytes = attrs?[.size] as? Int64
                    }
                }

                try await documentRepo.saveFromSync(doc)

                // Re-process document (generate chunks, embeddings, thumbnail) if it has a file
                if doc.fileURL != nil {
                    await reprocessDocument(doc)
                }

            case RecordMapper.RecordType.folder:
                guard let folder = RecordMapper.folder(from: record) else { return }
                try await folderRepo.saveFromSync(folder)

            case RecordMapper.RecordType.conversation:
                guard let conv = RecordMapper.conversation(from: record) else { return }
                try await conversationRepo.saveConversationFromSync(conv)

            case RecordMapper.RecordType.chatMessage:
                guard let msg = RecordMapper.chatMessage(from: record) else { return }
                try await conversationRepo.saveMessageFromSync(msg)

            default:
                print("SyncCoordinator: Unknown record type \(record.recordType)")
            }
        } catch {
            print("SyncCoordinator: Error applying incoming record — \(error)")
        }
    }

    private func applyIncomingDeletion(recordID: CKRecord.ID) async {
        let recordName = recordID.recordName

        do {
            // We don't know the exact type from a deletion, so try all
            // GRDB deleteOne silently succeeds if row doesn't exist
            try await db.dbWriter.write { db in
                _ = try? Document.deleteOne(db, key: recordName)
                _ = try? Folder.deleteOne(db, key: recordName)
                _ = try? Conversation.deleteOne(db, key: recordName)
                _ = try? PersistedChatMessage.deleteOne(db, key: recordName)
            }
        } catch {
            print("SyncCoordinator: Error applying deletion — \(error)")
        }
    }

    // MARK: - Handle Sent Changes (Confirmation)

    private func handleSentRecordZoneChanges(_ sentChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        Task {
            // Mark successfully saved records as synced
            for saved in sentChanges.savedRecords {
                let id = saved.recordID.recordName
                let changeTag = RecordMapper.encodeSystemFields(of: saved)

                switch saved.recordType {
                case RecordMapper.RecordType.document:
                    try? await documentRepo.markSynced(id: id, changeTag: changeTag)
                case RecordMapper.RecordType.folder:
                    try? await folderRepo.markSynced(id: id, changeTag: changeTag)
                case RecordMapper.RecordType.conversation:
                    try? await conversationRepo.markConversationSynced(id: id, changeTag: changeTag)
                case RecordMapper.RecordType.chatMessage:
                    try? await conversationRepo.markMessageSynced(id: id, changeTag: changeTag)
                default:
                    break
                }
            }

            // Handle successfully deleted records
            for deletedID in sentChanges.deletedRecordIDs {
                await removePendingDeletion(recordName: deletedID.recordName)
            }

            // Handle failures — re-schedule or log
            for failedSave in sentChanges.failedRecordSaves {
                let error = failedSave.error
                let recordID = failedSave.record.recordID

                switch error.code {
                case .serverRecordChanged:
                    // Conflict: server record wins (last-writer-wins using modifiedAt)
                    if let serverRecord = error.serverRecord {
                        await applyIncomingRecord(serverRecord)
                    }

                case .zoneNotFound:
                    // Create the zone and retry
                    await createCustomZone()
                    syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

                default:
                    print("SyncCoordinator: Failed to save \(recordID.recordName): \(error.localizedDescription)")
                    await MainActor.run {
                        syncError = "Error de sync: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Account Change

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            Task {
                await MainActor.run { iCloudAvailable = true; syncError = nil }
                await schedulePendingChanges()
            }
        case .signOut:
            Task { @MainActor in
                iCloudAvailable = false
                syncError = "Sesión de iCloud cerrada"
            }
        case .switchAccounts:
            // On account switch, mark everything for re-sync
            Task {
                await resetSyncState()
                await schedulePendingChanges()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Zone Management

    private func createCustomZone() async {
        let zone = CKRecordZone(zoneID: RecordMapper.zoneID)
        do {
            _ = try await container.privateCloudDatabase.save(zone)
            print("SyncCoordinator: Created custom zone \(RecordMapper.zoneName)")
        } catch {
            print("SyncCoordinator: Error creating zone — \(error)")
        }
    }

    // MARK: - Reset

    private func resetSyncState() async {
        do {
            try await db.dbWriter.write { db in
                try db.execute(sql: "DELETE FROM syncState")
                try db.execute(sql: "UPDATE document SET needsSyncPush = 1, syncChangeTag = NULL")
                try db.execute(sql: "UPDATE folder SET needsSyncPush = 1, syncChangeTag = NULL")
                try db.execute(sql: "UPDATE conversation SET needsSyncPush = 1, syncChangeTag = NULL")
                try db.execute(sql: "UPDATE chatMessage SET needsSyncPush = 1, syncChangeTag = NULL")
            }
        } catch {
            print("SyncCoordinator: Error resetting sync state — \(error)")
        }
    }

    // MARK: - Re-process Document

    private func reprocessDocument(_ doc: Document) async {
        // Trigger the document processor to re-extract, chunk, and embed
        Task {
            await DocumentProcessor.shared.process(documentId: doc.id)
        }
    }
}
