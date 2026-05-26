import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var documentCount = 0
    @Published var storageUsed = "..."
    @Published var showDeleteConfirmation = false
    @Published var userErrorMessage: String?
    @Published var selectedLanguage: AppLanguage = AppLanguage.current
    @Published var showAPIKeySheet = false
    @Published var pendingAPIKey = ""
    @Published var apiKeyVerificationState: APIKeyVerificationState = .idle

    private let repository = DocumentRepository()

    init() {
        APIKeyStore.migrateLegacyUserDefaultsKeyIfNeeded()
    }

    enum APIKeyVerificationState: Equatable {
        case idle, verifying, valid, invalid
    }

    var isGeminiKeyConfigured: Bool {
        !APIKeyStore.loadKey().isEmpty
    }

    var lang: AppLanguage { selectedLanguage }

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
        case .onDevice: return lang.aiActiveOnDevice
        case .cloud:    return lang.aiActiveCloud
        case nil:       return lang.aiBasicMode
        }
    }

    var aiFooterText: String {
        switch QAService.shared.activeProviderKind {
        case .onDevice: return lang.aiFooterOnDevice
        case .cloud:    return lang.aiFooterCloud
        case nil:       return lang.aiFooterBasic
        }
    }

    func verifyAndSaveAPIKey() {
        let trimmed = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKeyVerificationState = .verifying
        Task {
            let isValid = await GeminiQAProvider.verifyKey(trimmed)
            if isValid {
                try? APIKeyStore.saveKey(trimmed)
                apiKeyVerificationState = .valid
                showAPIKeySheet = false
                pendingAPIKey = ""
            } else {
                apiKeyVerificationState = .invalid
            }
        }
    }

    func removeAPIKey() {
        try? APIKeyStore.deleteOpenAIKey()
    }

    func changeLanguage(to language: AppLanguage) {
        selectedLanguage = language
        AppLanguage.current = language
    }

    func loadStats() async {
        do {
            let docs = try await repository.fetchAll()
            documentCount = docs.count

            let totalBytes = docs.compactMap(\.fileSizeBytes).reduce(0, +)
            storageUsed = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        } catch {
            AppLogger.error("Error cargando estadisticas: \(error.localizedDescription)")
            userErrorMessage = lang.errorLoadStats
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
                userErrorMessage = lang.errorReindex
            }
        }
    }

    func deleteAllData() {
        Task {
            do {
                // Delete all documents and files
                let docs = try await repository.fetchAll()
                for doc in docs {
                    try await repository.delete(id: doc.id)
                    repository.deleteFile(for: doc)
                }

                // Delete all conversations
                let conversationRepo = ConversationRepository()
                try await conversationRepo.deleteAllConversations()

                // Clear thumbnail cache
                await ThumbnailService.shared.clearCache()

                documentCount = 0
                storageUsed = "0 bytes"

                // Notify other views to reset
                NotificationCenter.default.post(name: .allDataDidDelete, object: nil)
            } catch {
                AppLogger.error("Error borrando datos: \(error.localizedDescription)")
                userErrorMessage = lang.errorDeleteAll
            }
        }
    }
}
