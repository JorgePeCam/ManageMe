import Foundation
import OSLog

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


enum AppLogger {
    private static let logger = Logger(subsystem: "com.manageme.app", category: "ManageMe")

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
