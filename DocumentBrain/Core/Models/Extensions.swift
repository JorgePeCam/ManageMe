import Foundation
import OSLog
import SwiftUI

// MARK: - Vector helpers

extension Array where Element == Float {
    func toData() -> Data {
        withUnsafeBytes { Data($0) }
    }
}

extension Data {
    func toFloatArray() -> [Float] {
        withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}

// MARK: - Logging

enum AppLogger {
    private static let logger = Logger(subsystem: "com.documentbrain.app", category: "DocumentBrain")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    /// Debug-only logging — completely stripped from release builds.
    static func debug(_ message: String) {
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

// MARK: - Document title cleaning

extension String {
    /// Cleans a raw filename into a human-readable document title.
    /// Removes hex hashes, UUIDs, Base64 tokens, underscores, and hyphens.
    static func cleanedDocumentTitle(_ raw: String) -> String {
        var title = raw

        // Remove leading UUID prefixes
        title = title.replacingOccurrences(
            of: "^(?:[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}[_ -]?)+",
            with: "", options: .regularExpression
        )
        // Remove leading hex hashes (16+ chars)
        title = title.replacingOccurrences(
            of: "^[A-Fa-f0-9]{16,}[_ -]?",
            with: "", options: .regularExpression
        )
        // Remove trailing Base64-like tokens
        title = title.replacingOccurrences(
            of: "[_ -][A-Za-z0-9+/]{12,}=*$",
            with: "", options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: "\\s+[A-Za-z0-9]{12,}$",
            with: "", options: .regularExpression
        )
        // Remove alphanumeric booking-ref codes (mixed letters+digits, 6+ chars)
        title = title.replacingOccurrences(
            of: "\\s+(?=[A-Za-z0-9]*[A-Z])(?=[A-Za-z0-9]*[0-9])[A-Z0-9]{6,}$",
            with: "", options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: "^(?=[A-Za-z0-9]*[A-Z])(?=[A-Za-z0-9]*[0-9])[A-Z0-9]{6,}[_ -]+",
            with: "", options: .regularExpression
        )
        // Replace separators with spaces, collapse runs of spaces
        title = title
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

        return title.isEmpty ? "Documento importado" : title
    }
}

// MARK: - Binding helpers

extension Binding where Value == Bool {
    /// Creates a `Bool` binding that is `true` while `optional` is non-nil,
    /// and sets it to `nil` when the binding is set to `false`.
    static func isPresent<T>(_ optional: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { optional.wrappedValue != nil },
            set: { if !$0 { optional.wrappedValue = nil } }
        )
    }
}

// MARK: - Cached DateFormatters

private let _timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private let _shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f
}()

extension Date {
    /// Formats as "HH:mm" for today, "d MMM" for older dates.
    var relativeFormatted: String {
        if Calendar.current.isDateInToday(self) {
            return _timeFormatter.string(from: self)
        } else if Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year) {
            return _shortDateFormatter.string(from: self)
        } else {
            return _shortDateFormatter.string(from: self)
        }
    }
}
