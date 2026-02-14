import Foundation

enum SharedContainerConfig {
    static let appGroupIdentifier = "group.Jorge-Perez-Campos.ManageMe"
    static let inboxDirectoryName = "SharedInbox"
}

extension Notification.Name {
    static let sharedInboxDidImportDocuments = Notification.Name("sharedInboxDidImportDocuments")
}

@MainActor
final class SharedInboxImporter {
    static let shared = SharedInboxImporter()

    private let fileManager = FileManager.default
    private let repository = DocumentRepository()
    private var isImporting = false

    func importPendingFiles() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        guard let inboxURL = sharedInboxURL() else { return }
        guard let urls = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let filesOnly = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        }

        guard !filesOnly.isEmpty else { return }

        var importedCount = 0
        for url in filesOnly {
            let didImport = await importSharedFile(at: url)
            if didImport {
                importedCount += 1
            }
        }

        if importedCount > 0 {
            NotificationCenter.default.post(name: .sharedInboxDidImportDocuments, object: nil)
        }
    }

    private func sharedInboxURL() -> URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SharedContainerConfig.appGroupIdentifier
        ) else {
            AppLogger.error("No se encontro contenedor App Group")
            return nil
        }

        let inboxURL = containerURL.appendingPathComponent(SharedContainerConfig.inboxDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: inboxURL.path) {
            try? fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        }
        return inboxURL
    }

    private func importSharedFile(at sourceURL: URL) async -> Bool {
        let fileType = Self.detectFileType(from: sourceURL)

        do {
            // File copy can be expensive for large PDFs/images; do it off the main actor.
            let (relativePath, fileSize) = try await Task.detached(priority: .utility) {
                try Self.copyToManagedStorage(from: sourceURL)
            }.value
            let title = Self.cleanTitle(from: sourceURL)

            let document = Document(
                title: title,
                fileType: fileType,
                fileURL: relativePath,
                fileSizeBytes: fileSize,
                sourceType: .files,
                processingStatus: .pending
            )

            try await repository.save(document)
            try fileManager.removeItem(at: sourceURL)
            await DocumentProcessor.shared.process(documentId: document.id)
            return true
        } catch {
            AppLogger.error("Error importando desde Share Extension: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated private static func copyToManagedStorage(from sourceURL: URL) throws -> (relativePath: String, fileSize: Int64) {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filesDir = documentsDir.appendingPathComponent("files", isDirectory: true)

        if !fileManager.fileExists(atPath: filesDir.path) {
            try fileManager.createDirectory(at: filesDir, withIntermediateDirectories: true)
        }

        let ext = sourceURL.pathExtension
        let fileName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let relativePath = "files/\(fileName)"
        let destinationURL = documentsDir.appendingPathComponent(relativePath)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return (relativePath, fileSize)
    }

    nonisolated private static func detectFileType(from url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp":
            return .image
        case "docx":
            return .docx
        case "xlsx":
            return .xlsx
        case "txt", "md", "csv", "rtf":
            return .text
        case "eml":
            return .email
        default:
            return .unknown
        }
    }

    private static func cleanTitle(from url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        let withoutPrefix = raw.replacingOccurrences(
            of: "^(?:[A-Fa-f0-9-]{36}-)+",
            with: "",
            options: .regularExpression
        )

        let normalized = withoutPrefix
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? "Documento compartido" : normalized
    }
}
