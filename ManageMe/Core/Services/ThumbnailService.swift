import UIKit
import PDFKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let fileManager = FileManager.default
    private var cache: [String: UIImage] = [:]

    /// Returns a thumbnail for the document, generating and caching it if needed
    func thumbnail(for document: Document) async -> UIImage? {
        // Check memory cache
        if let cached = cache[document.id] {
            return cached
        }

        // Check if thumbnail already saved on disk
        if let thumbURL = document.absoluteThumbnailURL,
           let image = UIImage(contentsOfFile: thumbURL.path) {
            cache[document.id] = image
            return image
        }

        // Generate thumbnail
        guard let fileURL = document.absoluteFileURL else { return nil }
        let image = await generateThumbnail(for: fileURL, fileType: document.fileTypeEnum)

        if let image {
            cache[document.id] = image
            // Save to disk asynchronously
            await saveThumbnail(image, for: document)
        }

        return image
    }

    /// Clears the memory cache
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Generation

    private func generateThumbnail(for url: URL, fileType: FileType) async -> UIImage? {
        switch fileType {
        case .pdf:
            return generatePDFThumbnail(url: url)
        case .image:
            return generateImageThumbnail(url: url)
        default:
            return nil
        }
    }

    private func generatePDFThumbnail(url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else { return nil }

        let bounds = page.bounds(for: .mediaBox)
        let targetWidth: CGFloat = 300
        let scale = targetWidth / bounds.width
        let targetSize = CGSize(width: targetWidth, height: bounds.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private func generateImageThumbnail(url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let original = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 300
        let scale: CGFloat
        if original.size.width > original.size.height {
            scale = maxDimension / original.size.width
        } else {
            scale = maxDimension / original.size.height
        }

        let targetSize = CGSize(
            width: original.size.width * scale,
            height: original.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    // MARK: - Persistence

    private func saveThumbnail(_ image: UIImage, for document: Document) async {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let thumbsDir = documentsDir.appendingPathComponent("Thumbnails", isDirectory: true)

        if !fileManager.fileExists(atPath: thumbsDir.path) {
            try? fileManager.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        }

        let thumbPath = thumbsDir.appendingPathComponent("\(document.id).jpg")
        try? data.write(to: thumbPath, options: .atomic)

        // Update document record with thumbnail path
        let relativePath = "Thumbnails/\(document.id).jpg"
        let repository = DocumentRepository()
        try? await repository.updateThumbnail(documentId: document.id, thumbnailURL: relativePath)
    }
}
