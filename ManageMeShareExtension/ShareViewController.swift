import UIKit
import UniformTypeIdentifiers

private enum ShareExtensionConfig {
    static let appGroupIdentifier = "group.Jorge-Perez-Campos.ManageMe"
    static let inboxDirectoryName = "SharedInbox"
}

final class ShareViewController: UIViewController {
    private let containerView = UIView()
    private let iconView = UIImageView()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let checkmarkView = UIImageView()
    private var hasStarted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            await processShare()
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        // Card container
        containerView.backgroundColor = .systemBackground
        containerView.layer.cornerRadius = 20
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.15
        containerView.layer.shadowRadius = 20
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // App icon
        iconView.image = UIImage(systemName: "brain.head.profile")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconView)

        // Activity indicator
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        containerView.addSubview(activityIndicator)

        // Checkmark (hidden initially)
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkView.tintColor = .systemGreen
        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.alpha = 0
        containerView.addSubview(checkmarkView)

        // Status label
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Guardando en ManageMe…"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusLabel)

        // Detail label
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.text = "Procesando contenido compartido"
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 280),

            iconView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 28),
            iconView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            activityIndicator.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),

            checkmarkView.centerXAnchor.constraint(equalTo: activityIndicator.centerXAnchor),
            checkmarkView.centerYAnchor.constraint(equalTo: activityIndicator.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 28),
            checkmarkView.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),

            detailLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            detailLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            detailLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -28),
        ])
    }

    // MARK: - Processing

    private func processShare() async {
        do {
            let writer = SharedInboxWriter()
            let result = try await writer.saveIncomingItems(from: extensionContext?.inputItems ?? [])

            await MainActor.run {
                activityIndicator.stopAnimating()

                if result.savedCount > 0 {
                    showSuccess(result: result)
                } else {
                    showEmpty()
                }
            }

            completeRequest(after: 1.2)
        } catch {
            await MainActor.run {
                activityIndicator.stopAnimating()
                showError()
            }

            completeRequest(after: 1.5)
        }
    }

    private func showSuccess(result: ShareImportResult) {
        checkmarkView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            self.checkmarkView.alpha = 1
            self.checkmarkView.transform = .identity
        }

        let itemWord = result.savedCount == 1 ? "elemento" : "elementos"
        statusLabel.text = "¡\(result.savedCount) \(itemWord) guardado\(result.savedCount == 1 ? "" : "s")!"

        let typeNames = result.fileTypes.map { fileTypeDisplayName($0) }
        let typeSummary = typeNames.joined(separator: ", ")
        detailLabel.text = "Abre ManageMe para procesarlos\n\(typeSummary)"
    }

    private func showEmpty() {
        iconView.image = UIImage(systemName: "questionmark.circle")
        iconView.tintColor = .systemOrange
        statusLabel.text = "Sin contenido compatible"
        detailLabel.text = "ManageMe acepta PDFs, imágenes, documentos Word, Excel y texto"
    }

    private func showError() {
        iconView.image = UIImage(systemName: "exclamationmark.triangle")
        iconView.tintColor = .systemRed
        statusLabel.text = "Error al guardar"
        detailLabel.text = "No se pudo guardar el contenido compartido"
    }

    private func fileTypeDisplayName(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "PDF"
        case "jpg", "jpeg", "png", "heic", "heif": return "Imagen"
        case "docx": return "Word"
        case "xlsx": return "Excel"
        case "txt", "md", "csv": return "Texto"
        default: return "Archivo"
        }
    }

    private func completeRequest(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - Import Result

private struct ShareImportResult {
    var savedCount: Int
    var fileTypes: [String]
}

// MARK: - Inbox Writer

private final class SharedInboxWriter {
    private let fileManager = FileManager.default

    func saveIncomingItems(from inputItems: [Any]) async throws -> ShareImportResult {
        let providers = extractProviders(from: inputItems)
        guard !providers.isEmpty else { return ShareImportResult(savedCount: 0, fileTypes: []) }

        let inboxURL = try ensureInboxDirectory()
        var savedCount = 0
        var fileTypes: [String] = []
        let hasBinaryPayload = providers.contains(where: hasBinaryFilePayload)

        for provider in providers {
            // Safari and other apps can expose the same share as file + plain text/URL.
            // When we have at least one real file payload, ignore text-only providers.
            if hasBinaryPayload && !hasBinaryFilePayload(provider) {
                continue
            }

            guard let sourceURL = try await loadSupportedFile(
                from: provider,
                allowURLFallback: !hasBinaryPayload
            ) else { continue }
            defer { try? fileManager.removeItem(at: sourceURL) }

            let destinationURL = uniqueDestinationURL(for: provider, sourceURL: sourceURL, in: inboxURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            savedCount += 1
            fileTypes.append(sourceURL.pathExtension)
        }

        return ShareImportResult(savedCount: savedCount, fileTypes: fileTypes)
    }

    private func extractProviders(from inputItems: [Any]) -> [NSItemProvider] {
        inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
    }

    private func hasBinaryFilePayload(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || provider.hasItemConformingToTypeIdentifier("org.openxmlformats.wordprocessingml.document")
            || provider.hasItemConformingToTypeIdentifier("org.openxmlformats.spreadsheetml.sheet")
    }

    private func ensureInboxDirectory() throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ShareExtensionConfig.appGroupIdentifier
        ) else {
            throw ShareExtensionError.missingAppGroupContainer
        }

        let inboxURL = containerURL.appendingPathComponent(ShareExtensionConfig.inboxDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: inboxURL.path) {
            try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        }
        return inboxURL
    }

    private func loadSupportedFile(from provider: NSItemProvider, allowURLFallback: Bool) async throws -> URL? {
        // PDF
        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            return try await loadFile(from: provider, typeIdentifier: UTType.pdf.identifier, fallbackExtension: "pdf")
        }

        // DOCX
        let docxType = "org.openxmlformats.wordprocessingml.document"
        if provider.hasItemConformingToTypeIdentifier(docxType) {
            return try await loadFile(from: provider, typeIdentifier: docxType, fallbackExtension: "docx")
        }

        // XLSX
        let xlsxType = "org.openxmlformats.spreadsheetml.sheet"
        if provider.hasItemConformingToTypeIdentifier(xlsxType) {
            return try await loadFile(from: provider, typeIdentifier: xlsxType, fallbackExtension: "xlsx")
        }

        // Images
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try await loadFile(from: provider, typeIdentifier: UTType.image.identifier, fallbackExtension: "jpg")
        }

        // Plain text (save as .txt file)
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return try await saveTextContent(from: provider)
        }

        // URL fallback
        if allowURLFallback && provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return try await saveURLAsTextFile(from: provider)
        }

        return nil
    }

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String, fallbackExtension: String) async throws -> URL {
        if let url = try await loadFileRepresentation(from: provider, typeIdentifier: typeIdentifier) {
            return url
        }

        if let data = try await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier) {
            let tempURL = fileManager.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(fallbackExtension)")
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        }

        throw ShareExtensionError.unsupportedPayload
    }

    private func loadFileRepresentation(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")

                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private func saveTextContent(from provider: NSItemProvider) async throws -> URL {
        guard let text = try await loadTextString(from: provider), !text.isEmpty else {
            throw ShareExtensionError.unsupportedPayload
        }

        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-texto.txt")
        guard let data = text.data(using: .utf8) else {
            throw ShareExtensionError.unsupportedPayload
        }
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func loadTextString(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }

                if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func saveURLAsTextFile(from provider: NSItemProvider) async throws -> URL {
        guard let urlString = try await loadURLString(from: provider) else {
            throw ShareExtensionError.unsupportedPayload
        }

        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-enlace.txt")
        let content = "Enlace compartido:\n\(urlString)\n"
        guard let data = content.data(using: .utf8) else {
            throw ShareExtensionError.unsupportedPayload
        }
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    private func loadURLString(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                    return
                }

                if let nsURL = item as? NSURL, let value = nsURL.absoluteString {
                    continuation.resume(returning: value)
                    return
                }

                if let text = item as? String {
                    continuation.resume(returning: text)
                    return
                }

                if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func uniqueDestinationURL(for provider: NSItemProvider, sourceURL: URL, in inboxURL: URL) -> URL {
        let rawName = provider.suggestedName ?? sourceURL.deletingPathExtension().lastPathComponent
        let sanitizedName = sanitizeFileName(rawName)
        let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString)-\(sanitizedName).\(ext)"
        return inboxURL.appendingPathComponent(fileName)
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let parts = name.components(separatedBy: invalidChars)
        let clean = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "archivo" : clean
    }
}

// MARK: - Errors

private enum ShareExtensionError: LocalizedError {
    case missingAppGroupContainer
    case unsupportedPayload

    var errorDescription: String? {
        switch self {
        case .missingAppGroupContainer:
            return "No se pudo abrir el contenedor compartido"
        case .unsupportedPayload:
            return "Contenido no soportado"
        }
    }
}
