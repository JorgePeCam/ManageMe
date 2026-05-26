import Foundation
import CoreML

final class EmbeddingService {
    /// Bump this string when the model file is replaced. Any mismatch with the
    /// stored UserDefaults value triggers a full re-index on next launch.
    static let modelVersion = "multi-qa-MiniLM-L6-cos-v1"
    static let embeddingDimension = 384

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
        // Use CPU for simulator compatibility. On device, .all enables Neural Engine.
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

    /// Returns a 384-dim L2-normalized embedding for the given text.
    func generateEmbedding(for text: String) async throws -> [Float] {
        let (inputIDs, mask) = try tokenizer.tokenizeToMLArrays(text: text)
        let output = try model.prediction(input_ids: inputIDs, attention_mask: mask)
        return extractEmbedding(from: output.embedding)
    }

    func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            results.append(embedding)
        }
        return results
    }

    private func extractEmbedding(from multiArray: MLMultiArray) -> [Float] {
        let dim = Self.embeddingDimension
        var embedding = [Float](repeating: 0, count: dim)
        for i in 0..<dim {
            embedding[i] = multiArray[[0, NSNumber(value: i)] as [NSNumber]].floatValue
        }
        return embedding
    }
}

enum EmbeddingError: LocalizedError {
    case vocabNotFound
    case modelNotAvailable

    var errorDescription: String? {
        switch self {
        case .vocabNotFound: return "No se encontró vocab.txt en el bundle"
        case .modelNotAvailable: return "El modelo de embeddings no está disponible"
        }
    }
}
