import Foundation

/// Protocol for Q&A providers (on-device or cloud API)
protocol QAProvider {
    func answer(query: String, context: [SearchResult]) async throws -> String
    var isAvailable: Bool { get }
    var name: String { get }
}

/// Orchestrates Q&A: tries on-device first, falls back to API
final class QAService {
    static let shared = QAService()

    private var providers: [QAProvider] = []

    private init() {
        // 1. Try Apple Foundation Models first (free, private)
        if #available(iOS 26, *) {
            providers.append(FoundationModelQAProvider())
        }

        // 2. Fall back to OpenAI API
        providers.append(OpenAIQAProvider())
    }

    /// Returns the first available provider, or nil
    var activeProvider: QAProvider? {
        providers.first { $0.isAvailable }
    }

    var activeProviderName: String {
        activeProvider?.name ?? "Ninguno"
    }

    var hasAnyProvider: Bool {
        activeProvider != nil
    }

    func answer(query: String, context: [SearchResult]) async throws -> String {
        guard let provider = activeProvider else {
            throw QAError.noProviderAvailable
        }
        return try await provider.answer(query: query, context: context)
    }

    /// Builds the system prompt for Q&A
    static func buildPrompt(query: String, context: [SearchResult]) -> String {
        var prompt = """
        Eres un asistente personal que responde preguntas basándose ÚNICAMENTE en los documentos del usuario.

        REGLAS:
        - Responde de forma concisa y directa
        - Solo usa información que aparezca en los fragmentos proporcionados
        - Si la información no está en los fragmentos, dilo claramente
        - Usa formato claro: fechas, horas, lugares en líneas separadas
        - Responde en el mismo idioma que la pregunta

        FRAGMENTOS DE DOCUMENTOS:
        """

        for (index, result) in context.enumerated() {
            prompt += "\n\n--- Documento: \(result.documentTitle) (fragmento \(index + 1)) ---\n"
            prompt += result.chunkContent
        }

        prompt += "\n\nPREGUNTA: \(query)"
        return prompt
    }
}

enum QAError: LocalizedError {
    case noProviderAvailable
    case apiKeyMissing
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noProviderAvailable:
            return "No hay ningún proveedor de IA configurado. Añade tu API key de OpenAI en Ajustes."
        case .apiKeyMissing:
            return "Falta la API key. Configúrala en Ajustes."
        case .apiError(let message):
            return "Error de la API: \(message)"
        }
    }
}
