import Foundation
import OSLog

// MARK: - Logging

enum AppLogger {
    nonisolated(unsafe) private static let logger = Logger(subsystem: "com.documentbrain.app", category: "DocumentBrain")

    nonisolated static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    nonisolated static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Debug-only logging — completely stripped from release builds.
    nonisolated static func debug(_ message: String) {
        #if DEBUG
        let msg = message
        logger.debug("\(msg, privacy: .public)")
        #endif
    }
}

// MARK: - UserDefaults keys

enum UserDefaultsKeys {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let appLanguage            = "app_language"
    static let ragDebugMode           = "rag_debug_mode"
    static let embeddingModelVersion  = "embeddingModelVersion"
    static let startupStorageError    = "startup_storage_error"
}
