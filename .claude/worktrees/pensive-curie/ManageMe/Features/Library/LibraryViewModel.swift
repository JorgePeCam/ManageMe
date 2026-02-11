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
            print("Error cargando documentos: \(error)")
        }
    }

    func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                Task { await importFile(from: url) }
            }
        case .failure(let error):
            print("Error importando: \(error)")
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
                print("Error eliminando: \(error)")
            }
        }
    }

    // MARK: - Import Logic

    private func importFile(from url: URL) async {
        let fileType = TextExtractionService.detectFileType(from: url)
        let title = url.deletingPathExtension().lastPathComponent

        do {
            let (relativePath, fileSize) = try repository.importFile(from: url, fileType: fileType)

            let document = Document(
                title: title,
                fileType: fileType,
                fileURL: relativePath,
                fileSizeBytes: fileSize,
                sourceType: .files,
                processingStatus: .pending
            )

            try await repository.save(document)
            documents.insert(document, at: 0)

            // Process in background
            Task.detached {
                await DocumentProcessor.shared.process(documentId: document.id)
                await self.refreshDocument(id: document.id)
            }
        } catch {
            print("Error importando archivo: \(error)")
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

            Task.detached {
                await DocumentProcessor.shared.process(documentId: document.id)
                await self.refreshDocument(id: document.id)
            }
        } catch {
            print("Error guardando foto: \(error)")
        }
    }

    private func refreshDocument(id: String) async {
        if let updated = try? await repository.fetchOne(id: id),
           let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index] = updated
        }
    }
}
