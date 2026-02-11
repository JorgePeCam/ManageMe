import SwiftUI

@main
struct ManageMeApp: App {
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
            MainTabView()
        }
    }
}
