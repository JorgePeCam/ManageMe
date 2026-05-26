import GRDB
import SwiftUI

@main
struct DocumentBrainApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        // Only filesystem work here — fast and required before any file access.
        do {
            try DocumentRepository.ensureStorageDirectories()
        } catch {
            print("Error creando directorios de almacenamiento: \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "startup_storage_error")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    MainTabView()
                        .task { await startupWork() }
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }

                if AppState.shared.isReindexing {
                    ReindexingOverlay()
                        .transition(.opacity)
                        .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: AppState.shared.isReindexing)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await SharedInboxImporter.shared.importPendingFiles() }
            if #available(iOS 17.0, *) {
                Task { await SyncCoordinator.shared.schedulePendingChanges() }
            }
        }
    }

    // MARK: - Async startup

    private func startupWork() async {
        // iCloud sync — network, must be async
        if #available(iOS 17.0, *) {
            SyncCoordinator.shared.start()
        }

        await SharedInboxImporter.shared.importPendingFiles()

        // Model version check: DB access happens here, off the first-frame path
        let needsReindex = await checkModelVersion()

        if needsReindex {
            await SettingsViewModel.reindexAllDocuments()
        } else {
            await DocumentProcessor.shared.recoverStuckDocuments()
        }

        // Pre-warm CoreML model in background so first search is instant
        Task.detached(priority: .background) {
            _ = EmbeddingService.shared
        }
    }

    private func checkModelVersion() async -> Bool {
        let storedVersion = UserDefaults.standard.string(forKey: "embeddingModelVersion") ?? ""
        guard storedVersion != EmbeddingService.modelVersion else { return false }

        try? await AppDatabase.shared.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM chunkVector")
            try db.execute(sql: "UPDATE document SET processingStatus = 'pending' WHERE processingStatus = 'ready'")
        }
        UserDefaults.standard.set(EmbeddingService.modelVersion, forKey: "embeddingModelVersion")
        return true
    }
}
