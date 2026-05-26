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
        case .xlsx:
            return try extractFromXLSX(url: url)
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

    // MARK: - XLSX Extraction

    private func extractFromXLSX(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let sharedStrings = parseSharedStrings(from: data)

        var sheetOutputs: [String] = []
        let workbookSheets = parseWorkbookSheets(from: data)

        if !workbookSheets.isEmpty {
            for sheet in workbookSheets {
                guard let sheetData = ZIPReader.extractFile(named: sheet.path, from: data) else { continue }
                let content = XLSXSheetParser(sharedStrings: sharedStrings).parse(data: sheetData)
                if !content.isEmpty {
                    sheetOutputs.append("Hoja: \(sheet.name)\n\(content)")
                }
            }
        }

        // Fallback for simple workbooks where workbook metadata is unavailable
        if sheetOutputs.isEmpty {
            for index in 1...30 {
                let path = "xl/worksheets/sheet\(index).xml"
                guard let sheetData = ZIPReader.extractFile(named: path, from: data) else { continue }
                let content = XLSXSheetParser(sharedStrings: sharedStrings).parse(data: sheetData)
                if !content.isEmpty {
                    sheetOutputs.append("Hoja \(index)\n\(content)")
                }
            }
        }

        let extracted = sheetOutputs.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !extracted.isEmpty else {
            throw ExtractionError.invalidFormat
        }

        return extracted
    }

    private func parseSharedStrings(from zipData: Data) -> [String] {
        guard let sharedStringsData = ZIPReader.extractFile(named: "xl/sharedStrings.xml", from: zipData) else {
            return []
        }
        return XLSXSharedStringsParser().parse(data: sharedStringsData)
    }

    private func parseWorkbookSheets(from zipData: Data) -> [XLSXSheetReference] {
        guard let workbookData = ZIPReader.extractFile(named: "xl/workbook.xml", from: zipData),
              let relsData = ZIPReader.extractFile(named: "xl/_rels/workbook.xml.rels", from: zipData) else {
            return []
        }

        let workbookSheets = XLSXWorkbookParser().parse(data: workbookData)
        let relationMap = XLSXWorkbookRelsParser().parse(data: relsData)

        return workbookSheets.compactMap { sheet in
            guard let target = relationMap[sheet.relationshipId] else { return nil }
            let normalizedPath: String
            if target.hasPrefix("xl/") {
                normalizedPath = target
            } else if target.hasPrefix("/") {
                normalizedPath = String(target.dropFirst())
            } else {
                normalizedPath = "xl/\(target)"
            }
            return XLSXSheetReference(name: sheet.name, path: normalizedPath)
        }
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

private struct XLSXSheetReference {
    let name: String
    let path: String
}

private struct XLSXWorkbookSheet {
    let name: String
    let relationshipId: String
}

private final class XLSXWorkbookParser: NSObject, XMLParserDelegate {
    private var sheets: [XLSXWorkbookSheet] = []

    func parse(data: Data) -> [XLSXWorkbookSheet] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName == "sheet" || elementName.hasSuffix(":sheet") else { return }
        guard let relationId = attributes["r:id"] ?? attributes["id"],
              !relationId.isEmpty else { return }
        let name = attributes["name"] ?? "Hoja"
        sheets.append(XLSXWorkbookSheet(name: name, relationshipId: relationId))
    }
}

private final class XLSXWorkbookRelsParser: NSObject, XMLParserDelegate {
    private var relations: [String: String] = [:]

    func parse(data: Data) -> [String: String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return relations
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName == "Relationship" else { return }
        guard let identifier = attributes["Id"],
              let target = attributes["Target"] else { return }

        let relationType = attributes["Type"] ?? ""
        if relationType.contains("/worksheet") {
            relations[identifier] = target
        }
    }
}

private final class XLSXSharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var currentString = ""
    private var insideSharedItem = false
    private var insideText = false

    func parse(data: Data) -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "si" || elementName.hasSuffix(":si") {
            insideSharedItem = true
            currentString = ""
        } else if insideSharedItem && (elementName == "t" || elementName.hasSuffix(":t")) {
            insideText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText {
            currentString += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "t" || elementName.hasSuffix(":t") {
            insideText = false
            return
        }

        if elementName == "si" || elementName.hasSuffix(":si") {
            strings.append(currentString.trimmingCharacters(in: .whitespacesAndNewlines))
            insideSharedItem = false
            currentString = ""
        }
    }
}

private final class XLSXSheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rowValues: [Int: String] = [:]
    private var rowLines: [String] = []

    private var currentCellReference: String?
    private var currentCellType: String?
    private var currentCellValue = ""

    private var isInsideValue = false
    private var isInsideInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
        super.init()
    }

    func parse(data: Data) -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        return rowLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "row" || elementName.hasSuffix(":row") {
            rowValues = [:]
            return
        }

        if elementName == "c" || elementName.hasSuffix(":c") {
            currentCellReference = attributes["r"]
            currentCellType = attributes["t"]
            currentCellValue = ""
            return
        }

        if elementName == "v" || elementName.hasSuffix(":v") {
            isInsideValue = true
            currentCellValue = ""
            return
        }

        if (elementName == "t" || elementName.hasSuffix(":t")),
           currentCellType == "inlineStr" {
            isInsideInlineText = true
            currentCellValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideValue || isInsideInlineText {
            currentCellValue += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "v" || elementName.hasSuffix(":v") {
            isInsideValue = false
            commitCurrentCellValue()
            return
        }

        if (elementName == "t" || elementName.hasSuffix(":t")),
           currentCellType == "inlineStr" {
            isInsideInlineText = false
            commitCurrentCellValue()
            return
        }

        if elementName == "c" || elementName.hasSuffix(":c") {
            currentCellReference = nil
            currentCellType = nil
            currentCellValue = ""
            return
        }

        if elementName == "row" || elementName.hasSuffix(":row") {
            let ordered = rowValues.keys.sorted().compactMap { rowValues[$0] }
            let line = ordered.joined(separator: " | ")
            if !line.isEmpty {
                rowLines.append(line)
            }
        }
    }

    private func commitCurrentCellValue() {
        let value: String
        switch currentCellType {
        case "s":
            if let index = Int(currentCellValue.trimmingCharacters(in: .whitespacesAndNewlines)),
               index >= 0, index < sharedStrings.count {
                value = sharedStrings[index]
            } else {
                value = currentCellValue
            }
        case "b":
            value = currentCellValue == "1" ? "TRUE" : "FALSE"
        default:
            value = currentCellValue
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let reference = currentCellReference,
           let column = Self.columnIndex(from: reference) {
            rowValues[column] = trimmed
        } else {
            let fallbackColumn = (rowValues.keys.max() ?? 0) + 1
            rowValues[fallbackColumn] = trimmed
        }
    }

    private static func columnIndex(from cellReference: String) -> Int? {
        let letters = cellReference.uppercased().prefix { $0.isLetter }
        guard !letters.isEmpty else { return nil }

        var index = 0
        for letter in letters {
            guard let ascii = letter.asciiValue else { return nil }
            let value = Int(ascii) - 64 // A = 1
            guard (1...26).contains(value) else { return nil }
            index = index * 26 + value
        }
        return index
    }
}

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
