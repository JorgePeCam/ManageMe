import Foundation

struct ChunkingService {
    /// Target characters per chunk (~300 tokens for Spanish/English)
    private let targetChunkSize = 1200

    /// Overlap in characters between consecutive chunks
    private let overlapSize = 200

    /// Splits text into overlapping chunks, breaking at sentence boundaries
    func chunk(text: String, documentId: String) -> [DocumentChunk] {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return [] }

        // If text is short enough, return as single chunk
        if cleanedText.count <= targetChunkSize {
            return [
                DocumentChunk(
                    documentId: documentId,
                    content: cleanedText,
                    chunkIndex: 0,
                    startOffset: 0,
                    endOffset: cleanedText.count
                )
            ]
        }

        var chunks: [DocumentChunk] = []
        var startIndex = cleanedText.startIndex
        var chunkIndex = 0

        while startIndex < cleanedText.endIndex {
            // Calculate the ideal end position
            let idealEnd = cleanedText.index(
                startIndex,
                offsetBy: targetChunkSize,
                limitedBy: cleanedText.endIndex
            ) ?? cleanedText.endIndex

            // Find a sentence boundary near the ideal end
            let endIndex = findSentenceBoundary(
                in: cleanedText,
                near: idealEnd,
                after: startIndex
            )

            let chunkContent = String(cleanedText[startIndex..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !chunkContent.isEmpty {
                let startOffset = cleanedText.distance(from: cleanedText.startIndex, to: startIndex)
                let endOffset = cleanedText.distance(from: cleanedText.startIndex, to: endIndex)

                chunks.append(DocumentChunk(
                    documentId: documentId,
                    content: chunkContent,
                    chunkIndex: chunkIndex,
                    startOffset: startOffset,
                    endOffset: endOffset
                ))
                chunkIndex += 1
            }

            // Move start position back by overlap amount
            if endIndex >= cleanedText.endIndex {
                break
            }

            let nextStart = cleanedText.index(
                endIndex,
                offsetBy: -overlapSize,
                limitedBy: startIndex
            ) ?? endIndex

            // Ensure we always make forward progress
            if nextStart <= startIndex {
                startIndex = endIndex
            } else {
                startIndex = nextStart
            }
        }

        return chunks
    }

    /// Finds the nearest sentence boundary (., !, ?) near the target position
    private func findSentenceBoundary(
        in text: String,
        near target: String.Index,
        after start: String.Index
    ) -> String.Index {
        // If we're at the end, return the end
        if target >= text.endIndex { return text.endIndex }

        let sentenceEnders: Set<Character> = [".", "!", "?", "\n"]

        // Search backwards from target for a sentence boundary (up to 200 chars back)
        let searchStart = text.index(
            target,
            offsetBy: -200,
            limitedBy: start
        ) ?? start

        var bestBoundary: String.Index?
        var current = target

        // Search backwards
        while current > searchStart {
            let prevIndex = text.index(before: current)
            if sentenceEnders.contains(text[prevIndex]) {
                bestBoundary = current
                break
            }
            current = prevIndex
        }

        // If no sentence boundary found, search forward a bit
        if bestBoundary == nil {
            current = target
            let searchEnd = text.index(
                target,
                offsetBy: 100,
                limitedBy: text.endIndex
            ) ?? text.endIndex

            while current < searchEnd {
                if sentenceEnders.contains(text[current]) {
                    bestBoundary = text.index(after: current)
                    break
                }
                current = text.index(after: current)
            }
        }

        return bestBoundary ?? target
    }
}
