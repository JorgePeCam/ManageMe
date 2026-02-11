import SwiftUI

@main
struct ManageMeApp: App {
    init() {
        try? DocumentRepository.ensureStorageDirectories()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
