import SwiftUI

@main
struct ManageMeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        do {
            try DocumentRepository.ensureStorageDirectories()
        } catch {
            print("Error creando directorios de almacenamiento: \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "startup_storage_error")
        }

        // Start iCloud sync
        if #available(iOS 17.0, *) {
            SyncCoordinator.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .task {
                        await SharedInboxImporter.shared.importPendingFiles()
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await SharedInboxImporter.shared.importPendingFiles()
            }
            // Re-schedule pending sync changes when app becomes active
            if #available(iOS 17.0, *) {
                Task {
                    await SyncCoordinator.shared.schedulePendingChanges()
                }
            }
        }
    }
}
