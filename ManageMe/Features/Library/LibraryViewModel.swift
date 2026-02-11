import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var showImporter = false
    @Published var showCamera = false
    @Published var filterType: FileType?
    @Published var userErrorMessage: String?

    private let repository = DocumentRepository()

    let allowedContentTypes: [UTType] = [
        .pdf, .image, .plainText,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data, // .docx
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data, // .xlsx
    ]

    var filteredDocuments: [Document] {
        guard let filterType else { return documents }
        return documents.filter { $0.fileType == filterType.rawValue }
    }

    func loadDocuments() async {
        do {
            documents = try await repository.fetchAll()
        } catch {
            AppLogger.error("Error cargando documentos: \(error.localizedDescription)")
            userErrorMessage = "No se pudieron cargar los documentos."
        }
    }

    func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                Task { await importFile(from: url) }
            }
        case .failure(let error):
            AppLogger.error("Error importando: \(error.localizedDescription)")
            userErrorMessage = "No se pudo importar el archivo seleccionado."
        }
    }

    func handleCameraCapture(image: UIImage) {
        Task {
            await importCameraImage(image)
        }
    }

    func deleteDocument(id: String) {
        Task {
            do {
                if let doc = documents.first(where: { $0.id == id }) {
                    repository.deleteFile(for: doc)
                }
                try await repository.delete(id: id)
                documents.removeAll { $0.id == id }
            } catch {
                AppLogger.error("Error eliminando: \(error.localizedDescription)")
                userErrorMessage = "No se pudo eliminar el documento."
            }
        }
    }

    // MARK: - Import Logic

    private func importFile(from url: URL) async {
        let fileType = TextExtractionService.detectFileType(from: url)
        // Capture the original filename BEFORE copying (copy renames to UUID)
        let title = url.deletingPathExtension().lastPathComponent

        do {
            let (relativePath, fileSize) = try repository.importFile(from: url, fileType: fileType)
            // Use original filename as title, cleaned up
            let cleanTitle = title
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            let document = Document(
                title: cleanTitle,
                fileType: fileType,
                fileURL: relativePath,
                fileSizeBytes: fileSize,
                sourceType: .files,
                processingStatus: .pending
            )

            try await repository.save(document)
            documents.insert(document, at: 0)

            // Process in background
            Task { [weak self] in
                await DocumentProcessor.shared.process(documentId: document.id)
                await self?.refreshDocument(id: document.id)
            }
        } catch {
            AppLogger.error("Error importando archivo: \(error.localizedDescription)")
            userErrorMessage = "No se pudo guardar el archivo importado."
        }
    }

    private func importCameraImage(_ image: UIImage) async {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "\(UUID().uuidString).jpg"
        let relativePath = "files/\(fileName)"
        let destinationURL = documentsDir.appendingPathComponent(relativePath)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return }

        do {
            try data.write(to: destinationURL)

            let document = Document(
                title: "Foto \(Date().formatted(date: .abbreviated, time: .shortened))",
                fileType: .image,
                fileURL: relativePath,
                fileSizeBytes: Int64(data.count),
                sourceType: .camera,
                processingStatus: .pending
            )

            try await repository.save(document)
            documents.insert(document, at: 0)

            Task { [weak self] in
                await DocumentProcessor.shared.process(documentId: document.id)
                await self?.refreshDocument(id: document.id)
            }
        } catch {
            AppLogger.error("Error guardando foto: \(error.localizedDescription)")
            userErrorMessage = "No se pudo guardar la foto capturada."
        }
    }

    private func refreshDocument(id: String) async {
        if let updated = try? await repository.fetchOne(id: id),
           let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index] = updated
        }
    }
}
