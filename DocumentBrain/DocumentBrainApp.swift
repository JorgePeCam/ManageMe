import GRDB
import SwiftUI

@main
struct DocumentBrainApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let needsStartupReindex: Bool

    init() {
        do {
            try DocumentRepository.ensureStorageDirectories()
        } catch {
            print("Error creando directorios de almacenamiento: \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "startup_storage_error")
        }

        // Detect model version change — wipe old vectors and schedule a startup reindex.
        let storedVersion = UserDefaults.standard.string(forKey: "embeddingModelVersion") ?? ""
        if storedVersion != EmbeddingService.modelVersion {
            needsStartupReindex = true
            // Clear stale vectors synchronously so search doesn't use wrong-dimension embeddings.
            try? AppDatabase.shared.dbWriter.barrierWriteWithoutTransaction { db in
                try db.execute(sql: "DELETE FROM chunkVector")
                try db.execute(sql: "UPDATE document SET processingStatus = 'pending' WHERE processingStatus = 'ready'")
            }
            UserDefaults.standard.set(EmbeddingService.modelVersion, forKey: "embeddingModelVersion")
        } else {
            needsStartupReindex = false
        }

        // Start iCloud sync
        if #available(iOS 17.0, *) {
            SyncCoordinator.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasCompletedOnboarding {
                    MainTabView()
                        .task {
                            await SharedInboxImporter.shared.importPendingFiles()
                            if needsStartupReindex {
                                await SettingsViewModel.reindexAllDocuments()
                            } else {
                                await DocumentProcessor.shared.recoverStuckDocuments()
                            }
                        }
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
            Task {
                await SharedInboxImporter.shared.importPendingFiles()
            }
            if #available(iOS 17.0, *) {
                Task {
                    await SyncCoordinator.shared.schedulePendingChanges()
                }
            }
        }
    }
}
