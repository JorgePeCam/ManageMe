import Foundation
import GRDB

enum FileType: String, Codable, CaseIterable {
    case pdf
    case image
    case docx
    case xlsx
    case text
    case email
    case unknown

    var displayName: String {
        switch self {
        case .pdf: return "PDF"
        case .image: return "Imagen"
        case .docx: return "Word"
        case .xlsx: return "Excel"
        case .text: return "Texto"
        case .email: return "Email"
        case .unknown: return "Otro"
        }
    }

    var systemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .docx: return "doc.text"
        case .xlsx: return "tablecells"
        case .text: return "doc.plaintext"
        case .email: return "envelope"
        case .unknown: return "doc"
        }
    }
}

enum ProcessingStatus: String, Codable {
    case pending
    case extracting
    case chunking
    case embedding
    case ready
    case error
}

enum SourceType: String, Codable {
    case files
    case camera
    case photos
    case manual
}

struct Document: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "document"

    var id: String
    var title: String
    var content: String
    var createdAt: Date
    var fileType: String
    var fileURL: String?
    var fileSizeBytes: Int64?
    var thumbnailURL: String?
    var sourceType: String
    var processingStatus: String
    var errorMessage: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        content: String = "",
        createdAt: Date = Date(),
        fileType: FileType = .unknown,
        fileURL: String? = nil,
        fileSizeBytes: Int64? = nil,
        thumbnailURL: String? = nil,
        sourceType: SourceType = .files,
        processingStatus: ProcessingStatus = .pending,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.fileType = fileType.rawValue
        self.fileURL = fileURL
        self.fileSizeBytes = fileSizeBytes
        self.thumbnailURL = thumbnailURL
        self.sourceType = sourceType.rawValue
        self.processingStatus = processingStatus.rawValue
        self.errorMessage = errorMessage
    }

    var fileTypeEnum: FileType {
        FileType(rawValue: fileType) ?? .unknown
    }

    var processingStatusEnum: ProcessingStatus {
        ProcessingStatus(rawValue: processingStatus) ?? .pending
    }

    var sourceTypeEnum: SourceType {
        SourceType(rawValue: sourceType) ?? .files
    }

    var isReady: Bool {
        processingStatusEnum == .ready
    }

    var absoluteFileURL: URL? {
        guard let fileURL else { return nil }
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent(fileURL)
    }

    var absoluteThumbnailURL: URL? {
        guard let thumbnailURL else { return nil }
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDir.appendingPathComponent(thumbnailURL)
    }
}
