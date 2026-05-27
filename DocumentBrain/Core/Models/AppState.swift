import Foundation

/// Global app state shared across views.
@Observable
final class AppState {
    static let shared = AppState()

    var isReindexing = false
    var reindexCompleted = 0
    var reindexTotal = 0

    var isDebugMode: Bool {
        get { UserDefaults.standard.bool(forKey: UserDefaultsKeys.ragDebugMode) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.ragDebugMode) }
    }

    var reindexProgress: Double {
        guard reindexTotal > 0 else { return 0 }
        return Double(reindexCompleted) / Double(reindexTotal)
    }

    var reindexStatusText: String {
        guard reindexTotal > 0 else { return "" }
        return "\(reindexCompleted) / \(reindexTotal)"
    }

    private init() {}
}
