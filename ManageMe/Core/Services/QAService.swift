import Foundation

/// Protocol for Q&A providers (on-device or cloud API)
protocol QAProvider {
    func answer(query: String, context: [SearchResult]) async throws -> String
    var isAvailable: Bool { get }
    var name: String { get }
    var kind: QAProviderKind { get }
}

/// Protocol for providers that support streaming responses
protocol StreamableQAProvider: QAProvider {
    func streamAnswer(query: String, context: [SearchResult], onUpdate: @escaping (String) -> Void) async throws
}

enum QAProviderKind {
    case onDevice
    case cloud
}

/// Orchestrates Q&A with automatic fallback chain:
/// 1. Apple Intelligence (on-device, free) — iOS 26+
/// 2. OpenAI GPT-4o-mini (cloud, fast) — silent fallback
/// 3. Extractive (no LLM) — last resort, handled by ChatViewModel
final class QAService {
    static let shared = QAService()

    private var providers: [QAProvider] = []

    private init() {
        // 1. Apple Foundation Models — free, private, on-device
        if #available(iOS 26, macOS 26, *) {
            providers.append(FoundationModelQAProvider())
        }

        // 2. OpenAI — silent cloud fallback
        providers.append(OpenAIQAProvider())
    }

    /// Returns the first available provider, or nil
    var activeProvider: QAProvider? {
        providers.first { $0.isAvailable }
    }

    var activeProviderName: String {
        activeProvider?.name ?? "No disponible"
    }

    var activeProviderKind: QAProviderKind? {
        activeProvider?.kind
    }

    var hasAnyProvider: Bool {
        activeProvider != nil
    }

    /// Whether the active provider supports streaming
    var canStream: Bool {
        activeProvider is StreamableQAProvider
    }

    /// Try each provider in order until one succeeds
    func answer(query: String, context: [SearchResult]) async throws -> String {
        var lastError: Error?

        for provider in providers where provider.isAvailable {
            do {
                return try await provider.answer(query: query, context: context)
            } catch {
                lastError = error
                continue // Try next provider
            }
        }

        throw lastError ?? QAError.noProviderAvailable
    }

    /// Stream the answer, falling back to non-streaming providers
    func streamAnswer(query: String, context: [SearchResult], onUpdate: @escaping (String) -> Void) async throws {
        var lastError: Error?

        for provider in providers where provider.isAvailable {
            do {
                if let streamable = provider as? StreamableQAProvider {
                    try await streamable.streamAnswer(query: query, context: context, onUpdate: onUpdate)
                } else {
                    let result = try await provider.answer(query: query, context: context)
                    onUpdate(result)
                }
                return // Success
            } catch {
                lastError = error
                continue // Try next provider
            }
        }

        throw lastError ?? QAError.noProviderAvailable
    }

    /// Backward-compatible prompt builder used by tests and providers.
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
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noProviderAvailable:
            return "No se pudo generar una respuesta. Inténtalo de nuevo."
        case .apiError(let message):
            return message
        }
    }
}
