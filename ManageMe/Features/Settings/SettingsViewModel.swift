import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var documentCount = 0
    @Published var storageUsed = "Calculando..."
    @Published var showDeleteConfirmation = false

    private let repository = DocumentRepository()

    var embeddingModelStatus: String {
        EmbeddingService.shared != nil ? "MiniLM (activo)" : "No disponible"
    }

    func loadStats() async {
        do {
            let docs = try await repository.fetchAll()
            documentCount = docs.count

            let totalBytes = docs.compactMap(\.fileSizeBytes).reduce(0, +)
            storageUsed = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        } catch {
            print("Error cargando estadisticas: \(error)")
        }
    }

    func reindexAll() {
        Task {
            let docs = try? await repository.fetchAll()
            for doc in docs ?? [] {
                await DocumentProcessor.shared.reprocess(documentId: doc.id)
            }
            await loadStats()
        }
    }

    func deleteAllData() {
        Task {
            do {
                let docs = try await repository.fetchAll()
                for doc in docs {
                    repository.deleteFile(for: doc)
                    try await repository.delete(id: doc.id)
                }
                documentCount = 0
                storageUsed = "0 bytes"
            } catch {
                print("Error borrando datos: \(error)")
            }
        }
    }
}
