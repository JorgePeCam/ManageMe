import Combine
import Foundation

@MainActor
final class DocumentDetailViewModel: ObservableObject {
    @Published var document: Document?
    @Published var previewURL: URL?
    @Published var isExtractingMetadata = false
    /// `true` after a manual extraction attempt that returned no structured data.
    @Published var metadataNotFound = false

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

    /// Manually re-triggers metadata extraction for an already-processed document.
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
            if let id = documentId {
                await load(documentId: id)
            }
            isExtractingMetadata = false
            // If still no metadata after extraction, surface a "not found" hint
            if self.document?.structuredDataDecoded == nil {
                metadataNotFound = true
            }
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
