import SwiftUI

@main
struct ManageMeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        do {
            try DocumentRepository.ensureStorageDirectories()
        } catch {
            AppLogger.error("Error creando directorios de almacenamiento: \(error.localizedDescription)")
            UserDefaults.standard.set(error.localizedDescription, forKey: "startup_storage_error")
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
        }
    }
}
