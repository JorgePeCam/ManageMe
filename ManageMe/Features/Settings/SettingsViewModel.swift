import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var documentCount = 0
    @Published var storageUsed = "Calculando..."
    @Published var showDeleteConfirmation = false
    @Published var apiKey: String = ""
    @Published var userErrorMessage: String?

    private let repository = DocumentRepository()

    init() {
        apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    }

    var embeddingModelStatus: String {
        EmbeddingService.shared != nil ? "MiniLM (activo)" : "No disponible"
    }

    var activeProviderName: String {
        QAService.shared.activeProviderName
    }

    func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "openai_api_key")
    }

    func loadStats() async {
        do {
            let docs = try await repository.fetchAll()
            documentCount = docs.count

            let totalBytes = docs.compactMap(\.fileSizeBytes).reduce(0, +)
            storageUsed = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        } catch {
            AppLogger.error("Error cargando estadisticas: \(error.localizedDescription)")
            userErrorMessage = "No se pudieron cargar las estadísticas."
        }
    }

    func reindexAll() {
        Task {
            do {
                let docs = try await repository.fetchAll()
                for doc in docs {
                    await DocumentProcessor.shared.reprocess(documentId: doc.id)
                }
                await loadStats()
            } catch {
                AppLogger.error("Error reindexando documentos: \(error.localizedDescription)")
                userErrorMessage = "No se pudieron reindexar los documentos."
            }
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
                AppLogger.error("Error borrando datos: \(error.localizedDescription)")
                userErrorMessage = "No se pudieron borrar todos los datos."
            }
        }
    }
}
