import XCTest
@testable import ManageMe

final class ManageMeTests: XCTestCase {
    func testSanitizeFTSQueryBuildsQuotedORQuery() {
        let query = "reunion, proyecto; sprint"

        let sanitized = ChunkRepository.sanitizeFTSQuery(query)

        XCTAssertEqual(sanitized, "\"reunion\" OR \"proyecto\" OR \"sprint\"")
    }

    func testSanitizeFTSQueryDropsSingleCharacterTokens() {
        let query = "a i plan b"

        let sanitized = ChunkRepository.sanitizeFTSQuery(query)

        XCTAssertEqual(sanitized, "\"plan\"")
    }

    func testBuildPromptContainsQuestionAndDocumentFragments() {
        let context = [
            SearchResult(
                id: "chunk-1",
                chunkContent: "La reunión es el martes a las 10:00 en Madrid.",
                documentId: "doc-1",
                documentTitle: "Agenda semanal",
                score: 0.9
            )
        ]

        let prompt = QAService.buildPrompt(query: "¿Cuándo es la reunión?", context: context)

        XCTAssertTrue(prompt.contains("PREGUNTA: ¿Cuándo es la reunión?"))
        XCTAssertTrue(prompt.contains("--- Documento: Agenda semanal (fragmento 1) ---"))
        XCTAssertTrue(prompt.contains("La reunión es el martes a las 10:00 en Madrid."))
    }

    func testCosineSimilarityReturnsOneForIdenticalVectors() {
        let vector: [Float] = [1, 2, 3]

        let similarity = VectorMath.cosineSimilarity(vector, vector)

        XCTAssertEqual(similarity, 1.0, accuracy: 0.0001)
    }

    func testCosineSimilarityReturnsZeroForMismatchedDimensions() {
        let similarity = VectorMath.cosineSimilarity([1, 2], [1, 2, 3])

        XCTAssertEqual(similarity, 0.0)
    }
}
