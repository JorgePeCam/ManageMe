import Foundation
import CoreML

final class BERTTokenizer {
    private let vocabulary: [String: Int]
    private let unknownToken = "[UNK]"
    private let startToken = "[CLS]"
    private let separatorToken = "[SEP]"
    private let padToken = "[PAD]"
    
    // Configuración del modelo (DistilUSE Multilingual usa 512 tokens máx)
    private let maxSequenceLength = 512
    
    init(vocabURL: URL) throws {
        let content = try String(contentsOf: vocabURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var vocab = [String: Int]()
        for (index, line) in lines.enumerated() {
            let key = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                vocab[key] = index
            }
        }
        self.vocabulary = vocab
    }
    
    /// Convierte un texto en los MLMultiArray que necesita el modelo
    func tokenizeToMLArrays(text: String) throws -> (inputIDs: MLMultiArray, attentionMask: MLMultiArray) {
        let tokens = tokenize(text)
        let ids = tokens.compactMap { vocabulary[$0] ?? vocabulary[unknownToken] }
        
        // Preparamos los arrays con la forma correcta [1, 512]
        let shape = [1, NSNumber(value: maxSequenceLength)]
        let inputIDsArray = try MLMultiArray(shape: shape, dataType: .int32)
        let maskArray = try MLMultiArray(shape: shape, dataType: .int32)
        
        // 1. Inicializamos todo a 0 (Padding)
        for i in 0..<maxSequenceLength {
            let index = [0, NSNumber(value: i)] as [NSNumber]
            inputIDsArray[index] = 0
            maskArray[index] = 0
        }
        
        // 2. Rellenamos con los datos reales: [CLS] + Tokens + [SEP]
        let finalIDs = [vocabulary[startToken]!] + ids + [vocabulary[separatorToken]!]
        let actualLength = min(finalIDs.count, maxSequenceLength)
        
        for i in 0..<actualLength {
            let index = [0, NSNumber(value: i)] as [NSNumber]
            inputIDsArray[index] = NSNumber(value: finalIDs[i])
            maskArray[index] = 1 // 1 significa "presta atención a esto"
        }
        
        return (inputIDsArray, maskArray)
    }
    
    // Lógica básica de WordPiece
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        // Normalización básica
        let cleanText = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        
        // Separamos por espacios y puntuación simple
        let words = cleanText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        
        for word in words {
            if vocabulary[word] != nil {
                tokens.append(word)
                continue
            }
            // Si la palabra no existe, usamos token desconocido
            tokens.append(unknownToken)
        }
        return tokens
    }
}
