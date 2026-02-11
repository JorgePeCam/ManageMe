import Foundation

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
