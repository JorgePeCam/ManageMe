import Foundation
import PDFKit
import Vision
import UniformTypeIdentifiers

struct TextExtractionService {

    /// Extracts text from a file based on its type
    func extractText(from url: URL, fileType: FileType) async throws -> String {
        switch fileType {
        case .pdf:
            return try await extractFromPDF(url: url)
        case .image:
            return try await extractFromImage(url: url)
        case .docx:
            return try extractFromDOCX(url: url)
        case .text:
            return try String(contentsOf: url, encoding: .utf8)
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    // MARK: - PDF Extraction

    private func extractFromPDF(url: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ExtractionError.cannotOpenFile
        }

        var fullText = ""
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Page has selectable text
                fullText += pageText + "\n\n"
            } else {
                // Scanned page - use OCR
                let pageText = try await ocrPage(page)
                fullText += pageText + "\n\n"
            }
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ocrPage(_ page: PDFPage) async throws -> String {
        // Render PDF page to image for OCR
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // Higher resolution for better OCR
        let imageSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: imageSize))
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        guard let cgImage = image.cgImage else {
            throw ExtractionError.ocrFailed
        }

        return try await performOCR(on: cgImage)
    }

    // MARK: - Image OCR

    private func extractFromImage(url: URL) async throws -> String {
        guard let imageData = try? Data(contentsOf: url),
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw ExtractionError.cannotOpenFile
        }

        return try await performOCR(on: cgImage)
    }

    private func performOCR(on cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es", "en"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - DOCX Extraction

    private func extractFromDOCX(url: URL) throws -> String {
        // DOCX files are ZIP archives containing XML
        // Extract word/document.xml from the ZIP without external dependencies
        let data = try Data(contentsOf: url)

        guard let xmlData = ZIPReader.extractFile(named: "word/document.xml", from: data) else {
            throw ExtractionError.invalidFormat
        }

        let parser = DOCXParser()
        return parser.parse(data: xmlData)
    }

    // MARK: - File Type Detection

    static func detectFileType(from url: URL) -> FileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "tiff", "bmp":
            return .image
        case "docx":
            return .docx
        case "xlsx":
            return .xlsx
        case "txt", "md", "csv", "rtf":
            return .text
        case "eml":
            return .email
        default:
            return .unknown
        }
    }
}

// MARK: - DOCX XML Parser

private class DOCXParser: NSObject, XMLParserDelegate {
    private var text = ""
    private var currentElement = ""
    private var isInsideTextElement = false

    func parse(data: Data) -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        currentElement = elementName
        // w:t elements contain the actual text content
        if elementName == "w:t" || elementName.hasSuffix(":t") {
            isInsideTextElement = true
        }
        // w:p elements represent paragraphs
        if elementName == "w:p" || elementName.hasSuffix(":p") {
            text += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideTextElement {
            text += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "w:t" || elementName.hasSuffix(":t") {
            isInsideTextElement = false
        }
    }
}

// MARK: - Errors

enum ExtractionError: LocalizedError {
    case cannotOpenFile
    case ocrFailed
    case invalidFormat
    case unsupportedFileType

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile: return "No se pudo abrir el archivo"
        case .ocrFailed: return "Error en el reconocimiento de texto (OCR)"
        case .invalidFormat: return "Formato de archivo no valido"
        case .unsupportedFileType: return "Tipo de archivo no soportado"
        }
    }
}
