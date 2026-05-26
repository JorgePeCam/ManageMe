import Foundation

/// Global app state shared across views.
@Observable
final class AppState {
    static let shared = AppState()

    var isReindexing = false
    var reindexCompleted = 0
    var reindexTotal = 0

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
