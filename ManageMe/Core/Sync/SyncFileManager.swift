import Foundation
import CloudKit

/// Manages file downloads from CKAsset for synced documents.
actor SyncFileManager {

    static let shared = SyncFileManager()

    private let fileManager = FileManager.default

    /// Downloads the CKAsset from a record and copies it into local storage.
    /// Returns the relative file path for the document.
    func importAsset(from record: CKRecord, fileType: FileType) -> String? {
        guard let asset = record["file"] as? CKAsset,
              let assetURL = asset.fileURL,
              fileManager.fileExists(atPath: assetURL.path) else {
            return nil
        }

        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filesDir = documentsDir.appendingPathComponent("files")

        // Ensure files directory exists
        if !fileManager.fileExists(atPath: filesDir.path) {
            try? fileManager.createDirectory(at: filesDir, withIntermediateDirectories: true)
        }

        let ext = extensionForFileType(fileType)
        let fileName = "\(UUID().uuidString).\(ext)"
        let relativePath = "files/\(fileName)"
        let destinationURL = documentsDir.appendingPathComponent(relativePath)

        do {
            try fileManager.copyItem(at: assetURL, to: destinationURL)
            return relativePath
        } catch {
            print("SyncFileManager: Error copiando asset — \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes the local file for a document that was remotely deleted.
    func deleteLocalFile(relativePath: String?) {
        guard let relativePath else { return }
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsDir.appendingPathComponent(relativePath)
        try? fileManager.removeItem(at: fileURL)
    }

    private func extensionForFileType(_ type: FileType) -> String {
        switch type {
        case .pdf: return "pdf"
        case .image: return "jpg"
        case .docx: return "docx"
        case .xlsx: return "xlsx"
        case .text: return "txt"
        case .email: return "eml"
        case .unknown: return "bin"
        }
    }
}
