import Combine
import EventKit
import Foundation

@MainActor
final class DocumentDetailViewModel: ObservableObject {
    @Published var document: Document?
    @Published var previewURL: URL?
    @Published var isExtractingMetadata = false
    /// `true` after a manual extraction attempt that returned no structured data.
    @Published var metadataNotFound = false

    // Calendar
    @Published var calendarEvent: EKEvent?
    @Published var showCalendarSheet = false
    @Published var calendarAccessDenied = false

    private let repository = DocumentRepository()
    private var documentId: String?

    func load(documentId: String) async {
        self.documentId = documentId
        do {
            document = try await repository.fetchOne(id: documentId)
        } catch {
            AppLogger.error("Error cargando documento: \(error)")
        }
    }

    /// Manually re-triggers metadata extraction (and barcode detection) for an already-processed document.
    func extractMetadata() {
        guard let document, document.isReady, !document.content.isEmpty else { return }
        isExtractingMetadata = true
        metadataNotFound = false
        Task {
            await DocumentProcessor.shared.extractMetadata(
                documentId: document.id,
                text: document.content,
                title: document.title
            )
            // Also re-scan for barcodes in case they were missed
            if let url = document.absoluteFileURL {
                await DocumentProcessor.shared.detectAndSaveBarcodes(
                    documentId: document.id,
                    fileURL: url,
                    fileType: document.fileTypeEnum
                )
            }
            if let id = documentId {
                await load(documentId: id)
            }
            isExtractingMetadata = false
            if self.document?.structuredDataDecoded == nil {
                metadataNotFound = true
            }
        }
    }

    // MARK: - Calendar

    func addToCalendar(metadata: StructuredDocumentData, documentTitle: String) {
        calendarAccessDenied = false
        Task {
            let granted = await EventKitService.shared.requestAccess()
            guard granted else {
                calendarAccessDenied = true
                return
            }
            guard let event = EventKitService.shared.makeEvent(from: metadata, documentTitle: documentTitle) else { return }
            calendarEvent = event
            showCalendarSheet = true
        }
    }

    func openPreview() {
        previewURL = document?.absoluteFileURL
    }

    func reprocess() {
        guard let documentId else { return }
        Task {
            await DocumentProcessor.shared.reprocess(documentId: documentId)
            await load(documentId: documentId)
        }
    }
}
