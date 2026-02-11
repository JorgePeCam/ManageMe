import Combine
import Foundation

@MainActor
final class DocumentDetailViewModel: ObservableObject {
    @Published var document: Document?
    @Published var previewURL: URL?

    private let repository = DocumentRepository()
    private var documentId: String?

    func load(documentId: String) async {
        self.documentId = documentId
        do {
            document = try await repository.fetchOne(id: documentId)
        } catch {
            print("Error cargando documento: \(error)")
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
