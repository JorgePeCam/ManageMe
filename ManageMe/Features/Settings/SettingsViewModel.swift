import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var documentCount = 0
    @Published var storageUsed = "Calculando..."
    @Published var showDeleteConfirmation = false
    @Published var openAIAPIKey = ""
    @Published var userErrorMessage: String?

    private let repository = DocumentRepository()

    init() {
        APIKeyStore.migrateLegacyUserDefaultsKeyIfNeeded()
        openAIAPIKey = APIKeyStore.loadOpenAIKey()
    }

    var embeddingModelStatus: String {
        EmbeddingService.shared != nil ? "MiniLM (activo)" : "No disponible"
    }

    var isAIAvailable: Bool {
        QAService.shared.hasAnyProvider
    }

    var isOnDeviceAIActive: Bool {
        QAService.shared.activeProviderKind == .onDevice
    }

    var activeProviderName: String {
        QAService.shared.activeProviderName
    }

    var aiStatusText: String {
        switch QAService.shared.activeProviderKind {
        case .onDevice:
            return "Activo — on-device"
        case .cloud:
            return "Activo — nube (OpenAI)"
        case nil:
            return "No disponible"
        }
    }

    var aiFooterText: String {
        switch QAService.shared.activeProviderKind {
        case .onDevice:
            return "Las respuestas se procesan en tu dispositivo. Privado y sin coste."
        case .cloud:
            return "Las respuestas se procesan en la nube (OpenAI). Requiere conexión."
        case nil:
            return "Activa Apple Intelligence o configura una API key de OpenAI para fallback en la nube."
        }
    }

    func saveOpenAIAPIKey() {
        do {
            try APIKeyStore.saveOpenAIKey(openAIAPIKey)
            openAIAPIKey = APIKeyStore.loadOpenAIKey()
        } catch {
            AppLogger.error("Error guardando API key en llavero: \(error.localizedDescription)")
            userErrorMessage = "No se pudo guardar la API key en el llavero."
        }
    }

    func clearOpenAIAPIKey() {
        do {
            try APIKeyStore.deleteOpenAIKey()
            openAIAPIKey = ""
        } catch {
            AppLogger.error("Error eliminando API key del llavero: \(error.localizedDescription)")
            userErrorMessage = "No se pudo eliminar la API key del llavero."
        }
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
                    try await repository.delete(id: doc.id)
                    repository.deleteFile(for: doc)
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
