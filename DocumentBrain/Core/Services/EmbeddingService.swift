import Foundation
import CoreML

final class EmbeddingService {
    static let shared: EmbeddingService? = {
        do {
            return try EmbeddingService()
        } catch {
            print("Error inicializando EmbeddingService: \(error)")
            return nil
        }
    }()

    private let model: MiniLM
    private let tokenizer: BERTTokenizer

    private init() throws {
        let config = MLModelConfiguration()
        // Use CPU for simulator compatibility. On device, .all enables Neural Engine
        #if targetEnvironment(simulator)
        config.computeUnits = .cpuOnly
        #else
        config.computeUnits = .all
        #endif

        self.model = try MiniLM(configuration: config)

        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw EmbeddingError.vocabNotFound
        }
        self.tokenizer = try BERTTokenizer(vocabURL: vocabURL)
    }

    /// Generates a semantic embedding vector for the given text
    func generateEmbedding(for text: String) async throws -> [Float] {
        let (inputIDs, mask) = try tokenizer.tokenizeToMLArrays(text: text)
        let output = try model.prediction(input_ids: inputIDs, attention_mask: mask)
        return extractMeanPooling(hiddenState: output.last_hidden_state)
    }

    /// Generates embeddings for multiple texts (batch processing)
    func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            results.append(embedding)
        }
        return results
    }

    private func extractMeanPooling(hiddenState: MLMultiArray) -> [Float] {
        let embeddingSize = 512
        var pooledEmbedding = [Float](repeating: 0, count: embeddingSize)

        for i in 0..<embeddingSize {
            let key = [0, 0, NSNumber(value: i)] as [NSNumber]
            pooledEmbedding[i] = hiddenState[key].floatValue
        }

        return pooledEmbedding
    }
}

enum EmbeddingError: LocalizedError {
    case vocabNotFound
    case modelNotAvailable

    var errorDescription: String? {
        switch self {
        case .vocabNotFound: return "No se encontro vocab.txt en el bundle"
        case .modelNotAvailable: return "El modelo de embeddings no esta disponible"
        }
    }
}
