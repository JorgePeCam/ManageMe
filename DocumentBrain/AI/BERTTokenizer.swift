import Foundation
import CoreML

final class BERTTokenizer {
    private let vocabulary: [String: Int]
    private let unknownToken = "[UNK]"
    private let startToken = "[CLS]"
    private let separatorToken = "[SEP]"
    private let padToken = "[PAD]"
    private let maxSequenceLength = 512
    private let maxWordLength = 200

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

    func tokenizeToMLArrays(text: String) throws -> (inputIDs: MLMultiArray, attentionMask: MLMultiArray) {
        let tokens = tokenize(text)
        let ids = tokens.compactMap { vocabulary[$0] ?? vocabulary[unknownToken] }

        let shape = [1, NSNumber(value: maxSequenceLength)]
        let inputIDsArray = try MLMultiArray(shape: shape, dataType: .int32)
        let maskArray = try MLMultiArray(shape: shape, dataType: .int32)

        for i in 0..<maxSequenceLength {
            let index = [0, NSNumber(value: i)] as [NSNumber]
            inputIDsArray[index] = 0
            maskArray[index] = 0
        }

        let finalIDs = [vocabulary[startToken]!] + ids + [vocabulary[separatorToken]!]
        let actualLength = min(finalIDs.count, maxSequenceLength)

        for i in 0..<actualLength {
            let index = [0, NSNumber(value: i)] as [NSNumber]
            inputIDsArray[index] = NSNumber(value: finalIDs[i])
            maskArray[index] = 1
        }

        return (inputIDsArray, maskArray)
    }

    // MARK: - Real WordPiece Tokenization

    private func tokenize(_ text: String) -> [String] {
        // 1. Normalize: lowercase, remove accents
        let normalized = text.lowercased()

        // 2. Split into words (by whitespace and punctuation)
        let words = splitIntoWords(normalized)

        // 3. Apply WordPiece to each word
        var tokens: [String] = []
        for word in words {
            let subTokens = wordPieceTokenize(word)
            tokens.append(contentsOf: subTokens)
        }

        return tokens
    }

    /// Splits text into individual words, separating punctuation as its own token
    private func splitIntoWords(_ text: String) -> [String] {
        var words: [String] = []
        var currentWord = ""

        for char in text {
            if char.isWhitespace {
                if !currentWord.isEmpty {
                    words.append(currentWord)
                    currentWord = ""
                }
            } else if char.isPunctuation || char.isSymbol {
                if !currentWord.isEmpty {
                    words.append(currentWord)
                    currentWord = ""
                }
                words.append(String(char))
            } else {
                currentWord.append(char)
            }
        }

        if !currentWord.isEmpty {
            words.append(currentWord)
        }

        return words
    }

    /// WordPiece tokenization: breaks a word into known subword units.
    /// Example: "Vietnam" -> ["vi", "##et", "##nam"] (if those subwords exist)
    private func wordPieceTokenize(_ word: String) -> [String] {
        if word.count > maxWordLength {
            return [unknownToken]
        }

        // Check if the whole word is in vocabulary
        if vocabulary[word] != nil {
            return [word]
        }

        var tokens: [String] = []
        var start = word.startIndex
        var isFirst = true

        while start < word.endIndex {
            var end = word.endIndex
            var found = false

            // Greedy longest-match-first: try the longest substring first
            while end > start {
                let substring = String(word[start..<end])
                let candidate = isFirst ? substring : "##\(substring)"

                if vocabulary[candidate] != nil {
                    tokens.append(candidate)
                    start = end
                    isFirst = false
                    found = true
                    break
                }

                // Try one character shorter
                end = word.index(before: end)
            }

            if !found {
                // No subword found at all — the whole word is unknown
                return [unknownToken]
            }
        }

        return tokens
    }
}
