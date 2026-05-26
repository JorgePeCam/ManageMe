import Foundation

actor DocumentProcessor {
    static let shared = DocumentProcessor()

    private let textExtractor = TextExtractionService()
    private let chunkingService = ChunkingService()
    private let documentRepo = DocumentRepository()
    private let chunkRepo = ChunkRepository()

    private let maxAttempts = 3

    // MARK: - Public API

    func process(documentId: String) async {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                try await performProcessing(documentId: documentId)
                return
            } catch {
                lastError = error
                AppLogger.error("[Processor] Intento \(attempt)/\(maxAttempts) fallido (\(documentId)): \(error.localizedDescription)")
                if attempt < maxAttempts {
                    // Exponential backoff: 2s, 4s
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    // Reset to pending so the status indicator doesn't stay stuck
                    try? await documentRepo.updateStatus(id: documentId, status: .pending)
                }
            }
        }

        await setError(documentId: documentId, message: lastError?.localizedDescription ?? "Error desconocido")
    }

    /// Reprocess a document from scratch (deletes existing chunks first).
    func reprocess(documentId: String) async {
        try? await chunkRepo.deleteChunks(forDocumentId: documentId)
        await process(documentId: documentId)
    }

    /// Resets documents stuck in intermediate states (crash recovery) and reprocesses them.
    func recoverStuckDocuments() async {
        guard let docs = try? await documentRepo.fetchAll() else { return }
        let stuck = docs.filter {
            switch $0.processingStatusEnum {
            case .extracting, .chunking, .embedding: return true
            default: return false
            }
        }
        guard !stuck.isEmpty else { return }
        AppLogger.error("[Processor] Recuperando \(stuck.count) documento(s) atascados")
        for doc in stuck {
            try? await documentRepo.updateStatus(id: doc.id, status: .pending)
            await process(documentId: doc.id)
        }
    }

    // MARK: - Core Processing

    private func performProcessing(documentId: String) async throws {
        guard let embeddingService = EmbeddingService.shared else {
            throw ProcessingError.embeddingModelUnavailable
        }

        guard let document = try await documentRepo.fetchOne(id: documentId) else {
            throw ProcessingError.documentNotFound
        }

        // 1. Extract text
        try await documentRepo.updateStatus(id: documentId, status: .extracting)

        var extractedText = ""
        if let fileURL = document.absoluteFileURL {
            extractedText = try await textExtractor.extractText(from: fileURL, fileType: document.fileTypeEnum)
        } else if !document.content.isEmpty {
            extractedText = document.content
        }

        guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProcessingError.noTextExtracted
        }

        try await documentRepo.updateContent(id: documentId, content: extractedText)

        // 2. Chunk
        try await documentRepo.updateStatus(id: documentId, status: .chunking)
        let chunks = chunkingService.chunk(text: extractedText, documentId: documentId)

        guard !chunks.isEmpty else {
            throw ProcessingError.noChunksGenerated
        }

        // 3. Embed
        try await documentRepo.updateStatus(id: documentId, status: .embedding)

        var chunksWithEmbeddings: [(chunk: DocumentChunk, embedding: [Float])] = []
        for chunk in chunks {
            let embedding = try await embeddingService.generateEmbedding(for: chunk.content)
            chunksWithEmbeddings.append((chunk, embedding))
        }

        // 4. Save
        try await chunkRepo.saveChunks(chunksWithEmbeddings)
        try await documentRepo.updateStatus(id: documentId, status: .ready)
    }

    private func setError(documentId: String, message: String) async {
        try? await documentRepo.updateStatus(id: documentId, status: .error, error: message)
    }
}

// MARK: - Errors

private enum ProcessingError: LocalizedError {
    case embeddingModelUnavailable
    case documentNotFound
    case noTextExtracted
    case noChunksGenerated

    var errorDescription: String? {
        switch self {
        case .embeddingModelUnavailable: return "Modelo de IA no disponible"
        case .documentNotFound: return "Documento no encontrado"
        case .noTextExtracted: return "No se pudo extraer texto del archivo"
        case .noChunksGenerated: return "No se generaron fragmentos de texto"
        }
    }
}
