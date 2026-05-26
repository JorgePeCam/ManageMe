import Foundation

struct ChunkingService {
    // ~200 tokens ≈ 800 chars — tighter chunks improve Q&A embedding precision
    private let targetChunkChars = 800
    // Overlap: carry the last paragraph of the previous chunk (capped at this many chars)
    private let maxOverlapChars = 250
    // Paragraphs shorter than this are merged with the next one
    private let minParagraphChars = 60

    func chunk(text: String, documentId: String) -> [DocumentChunk] {
        let cleaned = preprocess(text)
        guard !cleaned.isEmpty else { return [] }

        let paragraphs = splitIntoParagraphs(cleaned)
        let merged = mergeTinyParagraphs(paragraphs)
        return buildChunks(from: merged, documentId: documentId)
    }

    // MARK: - Pre-processing

    private func preprocess(_ text: String) -> String {
        // Collapse 3+ consecutive newlines into 2, normalise whitespace within lines
        var result = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
            .joined(separator: "\n")

        // Collapse runs of 3+ newlines
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Paragraph splitting

    private func splitIntoParagraphs(_ text: String) -> [String] {
        // Primary split: blank lines
        let blocks = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Secondary: if a block is still very long, split it at sentence boundaries
        return blocks.flatMap { splitLongBlock($0) }
    }

    private func splitLongBlock(_ block: String) -> [String] {
        guard block.count > targetChunkChars * 2 else { return [block] }

        let sentences = splitIntoSentences(block)
        var result: [String] = []
        var current = ""

        for sentence in sentences {
            let candidate = current.isEmpty ? sentence : current + " " + sentence
            if candidate.count > targetChunkChars && !current.isEmpty {
                result.append(current)
                current = sentence
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Merge tiny paragraphs

    private func mergeTinyParagraphs(_ paragraphs: [String]) -> [String] {
        var result: [String] = []
        var pending = ""

        for paragraph in paragraphs {
            if pending.isEmpty {
                pending = paragraph
            } else if pending.count < minParagraphChars {
                pending += "\n\n" + paragraph
            } else {
                result.append(pending)
                pending = paragraph
            }
        }
        if !pending.isEmpty { result.append(pending) }
        return result
    }

    // MARK: - Chunk assembly

    private func buildChunks(from paragraphs: [String], documentId: String) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        var currentParagraphs: [String] = []
        var currentLength = 0
        var overlapParagraph: String? = nil  // last paragraph of previous chunk

        func flush() {
            guard !currentParagraphs.isEmpty else { return }
            var parts: [String] = []
            if let overlap = overlapParagraph {
                parts.append(overlap)
            }
            parts.append(contentsOf: currentParagraphs)
            let content = parts.joined(separator: "\n\n")
            chunks.append(DocumentChunk(
                documentId: documentId,
                content: content,
                chunkIndex: chunks.count
            ))
            // Carry last paragraph as overlap for the next chunk
            overlapParagraph = currentParagraphs.last.flatMap {
                $0.count <= maxOverlapChars ? $0 : String($0.suffix(maxOverlapChars))
            }
            currentParagraphs = []
            currentLength = 0
        }

        for paragraph in paragraphs {
            let addedLength = currentLength == 0 ? paragraph.count : currentLength + 2 + paragraph.count
            if addedLength > targetChunkChars && !currentParagraphs.isEmpty {
                flush()
            }
            currentParagraphs.append(paragraph)
            currentLength = currentParagraphs.reduce(0) { $0 + $1.count + 2 }
        }
        flush()

        return chunks
    }

    // MARK: - Sentence splitting

    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for (i, char) in text.enumerated() {
            current.append(char)
            if ".!?\n".contains(char) {
                // Avoid splitting on abbreviations like "Sr." or decimal numbers
                let next = text.index(text.startIndex, offsetBy: i + 1, limitedBy: text.endIndex)
                let nextChar: Character? = next.flatMap { $0 < text.endIndex ? text[$0] : nil }
                let isAbbreviation = nextChar?.isLetter == true
                if !isAbbreviation {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { sentences.append(trimmed) }
                    current = ""
                }
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { sentences.append(trimmed) }
        return sentences
    }
}
