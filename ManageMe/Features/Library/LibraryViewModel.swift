import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var folders: [Folder] = []
    @Published var showImporter = false
    @Published var showCamera = false
    @Published var filterType: FileType?
    @Published var userErrorMessage: String?

    // Folder navigation
    @Published var currentFolderId: String?
    @Published var folderPath: [Folder] = []
    @Published var documentCounts: [String: Int] = [:]

    private let repository = DocumentRepository()
    private let folderRepository = FolderRepository()

    let allowedContentTypes: [UTType] = [
        .pdf, .image, .plainText,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data, // .docx
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data, // .xlsx
    ]

    var filteredDocuments: [Document] {
        guard let filterType else { return documents }
        return documents.filter { $0.fileType == filterType.rawValue }
    }

    var isInFolder: Bool {
        currentFolderId != nil
    }

    var currentFolderName: String {
        folderPath.last?.name ?? "Biblioteca"
    }

    func loadDocuments() async {
        do {
            // Load documents for current folder
            documents = try await repository.fetchByFolder(currentFolderId)

            // Load subfolders
            if let folderId = currentFolderId {
                folders = try await folderRepository.fetchChildren(of: folderId)
            } else {
                folders = try await folderRepository.fetchRootFolders()
            }

            // Load document counts for visible folders
            var counts: [String: Int] = [:]
            for folder in folders {
                counts[folder.id] = try await folderRepository.documentCount(folderId: folder.id)
            }
            documentCounts = counts
        } catch {
            AppLogger.error("Error cargando documentos: \(error.localizedDescription)")
            userErrorMessage = "No se pudieron cargar los documentos."
        }
    }

    // MARK: - Folder Navigation

    func navigateToFolder(_ folder: Folder) {
        folderPath.append(folder)
        currentFolderId = folder.id
        Task { await loadDocuments() }
    }

    func navigateBack() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        currentFolderId = folderPath.last?.id
        Task { await loadDocuments() }
    }

    func navigateToRoot() {
        folderPath = []
        currentFolderId = nil
        Task { await loadDocuments() }
    }

    // MARK: - Folder CRUD

    func createFolder(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            do {
                let folder = Folder(name: trimmed, parentFolderId: currentFolderId)
                try await folderRepository.save(folder)
                await loadDocuments()
            } catch {
                AppLogger.error("Error creando carpeta: \(error.localizedDescription)")
                userErrorMessage = "No se pudo crear la carpeta."
            }
        }
    }

    func renameFolder(_ folder: Folder, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            do {
                var updated = folder
                updated.name = trimmed
                try await folderRepository.update(updated)
                await loadDocuments()
            } catch {
                AppLogger.error("Error renombrando carpeta: \(error.localizedDescription)")
                userErrorMessage = "No se pudo renombrar la carpeta."
            }
        }
    }

    func deleteFolder(id: String) {
        Task {
            do {
                try await folderRepository.delete(id: id)
                await loadDocuments()
            } catch {
                AppLogger.error("Error eliminando carpeta: \(error.localizedDescription)")
                userErrorMessage = "No se pudo eliminar la carpeta."
            }
        }
    }

    // MARK: - Move Documents

    func moveDocument(_ documentId: String, toFolder folderId: String?) {
        Task {
            do {
                try await repository.moveToFolder(documentId: documentId, folderId: folderId)
                await loadDocuments()
            } catch {
                AppLogger.error("Error moviendo documento: \(error.localizedDescription)")
                userErrorMessage = "No se pudo mover el documento."
            }
        }
    }

    // MARK: - Document CRUD

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
                let doc = documents.first(where: { $0.id == id })
                try await repository.delete(id: id)
                if let doc {
                    repository.deleteFile(for: doc)
                }
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
        let title = url.deletingPathExtension().lastPathComponent

        do {
            let (relativePath, fileSize) = try repository.importFile(from: url, fileType: fileType)
            let cleanTitle = title
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            let document = Document(
                title: cleanTitle,
                fileType: fileType,
                fileURL: relativePath,
                fileSizeBytes: fileSize,
                sourceType: .files,
                processingStatus: .pending,
                folderId: currentFolderId
            )

            try await repository.save(document)
            documents.insert(document, at: 0)

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
                processingStatus: .pending,
                folderId: currentFolderId
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
