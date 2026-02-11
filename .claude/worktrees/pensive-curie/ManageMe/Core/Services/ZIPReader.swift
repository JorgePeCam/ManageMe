import Foundation
import Compression

/// Minimal ZIP reader for extracting specific files from ZIP archives (like DOCX, XLSX).
/// Supports only Deflate and Store compression methods, which covers virtually all Office files.
enum ZIPReader {

    /// Extracts a specific file from a ZIP archive
    static func extractFile(named targetPath: String, from zipData: Data) -> Data? {
        return zipData.withUnsafeBytes { buffer -> Data? in
            guard let basePtr = buffer.baseAddress else { return nil }
            let bytes = basePtr.assumingMemoryBound(to: UInt8.self)
            let size = zipData.count

            var offset = 0
            while offset + 30 <= size {
                // Local file header signature = 0x04034b50
                guard bytes[offset] == 0x50,
                      bytes[offset + 1] == 0x4b,
                      bytes[offset + 2] == 0x03,
                      bytes[offset + 3] == 0x04 else {
                    break
                }

                let compressionMethod = UInt16(bytes[offset + 8]) | (UInt16(bytes[offset + 9]) << 8)
                let compressedSize = Int(UInt32(bytes[offset + 18])
                    | (UInt32(bytes[offset + 19]) << 8)
                    | (UInt32(bytes[offset + 20]) << 16)
                    | (UInt32(bytes[offset + 21]) << 24))
                let uncompressedSize = Int(UInt32(bytes[offset + 22])
                    | (UInt32(bytes[offset + 23]) << 8)
                    | (UInt32(bytes[offset + 24]) << 16)
                    | (UInt32(bytes[offset + 25]) << 24))
                let fileNameLength = Int(UInt16(bytes[offset + 26]) | (UInt16(bytes[offset + 27]) << 8))
                let extraFieldLength = Int(UInt16(bytes[offset + 28]) | (UInt16(bytes[offset + 29]) << 8))

                let fileNameStart = offset + 30
                guard fileNameStart + fileNameLength <= size else { break }

                let fileNameData = Data(bytes: bytes + fileNameStart, count: fileNameLength)
                let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

                let dataStart = fileNameStart + fileNameLength + extraFieldLength
                guard dataStart + compressedSize <= size else { break }

                if fileName == targetPath {
                    let compressedData = Data(bytes: bytes + dataStart, count: compressedSize)

                    switch compressionMethod {
                    case 0: // Store (no compression)
                        return compressedData
                    case 8: // Deflate
                        return decompressDeflate(compressedData, expectedSize: uncompressedSize)
                    default:
                        return nil
                    }
                }

                offset = dataStart + compressedSize
            }

            return nil
        }
    }

    private static func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        let bufferSize = max(expectedSize, data.count * 4)
        var destinationBuffer = Data(count: bufferSize)

        let decompressedSize = data.withUnsafeBytes { srcBuffer -> Int in
            destinationBuffer.withUnsafeMutableBytes { dstBuffer -> Int in
                guard let srcPtr = srcBuffer.baseAddress,
                      let dstPtr = dstBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstPtr.assumingMemoryBound(to: UInt8.self),
                    bufferSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decompressedSize > 0 else { return nil }
        return destinationBuffer.prefix(decompressedSize)
    }
}
