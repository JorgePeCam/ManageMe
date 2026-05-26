import Foundation

actor DocumentProcessor {
    static let shared = DocumentProcessor()

    private let textExtractor = TextExtractionService()
    private let chunkingService = ChunkingService()
    private let documentRepo = DocumentRepository()
    private let chunkRepo = ChunkRepository()

    /// Processes a document: extract text -> chunk -> embed -> store
    func process(documentId: String) async {
        guard let embeddingService = EmbeddingService.shared else {
            await setError(documentId: documentId, message: "Modelo de IA no disponible")
            return
        }

        do {
            // 1. Fetch the document
            guard let document = try await documentRepo.fetchOne(id: documentId) else {
                return
            }

            // 2. Extract text
            try await documentRepo.updateStatus(id: documentId, status: .extracting)

            var extractedText = ""
            if let fileURL = document.absoluteFileURL {
                extractedText = try await textExtractor.extractText(
                    from: fileURL,
                    fileType: document.fileTypeEnum
                )
            } else if !document.content.isEmpty {
                extractedText = document.content
            }

            guard !extractedText.isEmpty else {
                await setError(documentId: documentId, message: "No se pudo extraer texto del archivo")
                return
            }

            // Store extracted text
            try await documentRepo.updateContent(id: documentId, content: extractedText)

            // 3. Chunk text
            try await documentRepo.updateStatus(id: documentId, status: .chunking)
            let chunks = chunkingService.chunk(text: extractedText, documentId: documentId)

            guard !chunks.isEmpty else {
                await setError(documentId: documentId, message: "No se generaron fragmentos de texto")
                return
            }

            // 4. Generate embeddings
            try await documentRepo.updateStatus(id: documentId, status: .embedding)

            var chunksWithEmbeddings: [(chunk: DocumentChunk, embedding: [Float])] = []
            for chunk in chunks {
                let embedding = try await embeddingService.generateEmbedding(for: chunk.content)
                chunksWithEmbeddings.append((chunk, embedding))
            }

            // 5. Save chunks and vectors
            try await chunkRepo.saveChunks(chunksWithEmbeddings)

            // 6. Mark as ready
            try await documentRepo.updateStatus(id: documentId, status: .ready)

        } catch {
            await setError(documentId: documentId, message: error.localizedDescription)
        }
    }

    private func setError(documentId: String, message: String) async {
        try? await documentRepo.updateStatus(id: documentId, status: .error, error: message)
    }

    /// Reprocesses a document (deletes existing chunks first)
    func reprocess(documentId: String) async {
        try? await chunkRepo.deleteChunks(forDocumentId: documentId)
        await process(documentId: documentId)
    }
}
