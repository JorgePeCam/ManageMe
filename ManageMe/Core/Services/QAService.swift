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
/// 1. Gemini Flash (cloud, free) — best quality, primary
/// 2. Apple Intelligence (on-device, free) — offline/rate-limit fallback
/// 3. Extractive (no LLM) — last resort, handled by ChatViewModel
final class QAService {
    static let shared = QAService()

    private var providers: [QAProvider] = []

    private init() {
        // 1. Gemini Flash — best quality, free tier (20 queries/day per device)
        providers.append(GeminiQAProvider())

        // 2. Apple Foundation Models — fallback when offline or Gemini limit reached
        if #available(iOS 26, macOS 26, *) {
            providers.append(FoundationModelQAProvider())
        }
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

        AppLogger.debug("[QAService] Providers: \(providers.map { "\($0.name) available=\($0.isAvailable)" })")
        for provider in providers where provider.isAvailable {
            do {
                AppLogger.debug("[QAService] Trying provider: \(provider.name)")
                let result = try await provider.answer(query: query, context: context)
                AppLogger.debug("[QAService] ✅ \(provider.name) succeeded")
                return result
            } catch {
                AppLogger.debug("[QAService] ⚠️ \(provider.name) failed: \(error.localizedDescription)")
                lastError = error
                continue // Try next provider
            }
        }

        throw lastError ?? QAError.noProviderAvailable
    }

    /// Stream the answer, falling back to non-streaming providers
    func streamAnswer(query: String, context: [SearchResult], onUpdate: @escaping (String) -> Void) async throws {
        var lastError: Error?

        AppLogger.debug("[QAService] Stream — Providers: \(providers.map { "\($0.name) available=\($0.isAvailable)" })")
        for provider in providers where provider.isAvailable {
            do {
                AppLogger.debug("[QAService] Stream — Trying: \(provider.name)")
                if let streamable = provider as? StreamableQAProvider {
                    try await streamable.streamAnswer(query: query, context: context, onUpdate: onUpdate)
                } else {
                    let result = try await provider.answer(query: query, context: context)
                    onUpdate(result)
                }
                AppLogger.debug("[QAService] ✅ Stream — \(provider.name) succeeded")
                return // Success
            } catch {
                AppLogger.debug("[QAService] ⚠️ Stream — \(provider.name) failed: \(error.localizedDescription)")
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
        - Responde SOLO con información que aparezca en los fragmentos proporcionados.
        - Si los fragmentos NO contienen información relevante, responde EXACTAMENTE: "No encontré información sobre esto en tus documentos."
        - NO inventes ni supongas información que no esté en los fragmentos.
        - Responde en el mismo idioma que la pregunta.
        - Cita el nombre del documento cuando sea relevante.

        ESTILO DE RESPUESTA:
        - Desarrolla la respuesta con detalle: incluye todos los datos relevantes que encuentres (fechas, nombres, tecnologías, responsabilidades, cantidades, etc.)
        - Organiza la información de forma clara usando párrafos, listas o secciones según convenga.
        - Si hay información distribuida en varios fragmentos del mismo documento, sintetízala en una respuesta coherente y completa.
        - No te limites a una línea; elabora una respuesta completa que responda la pregunta del usuario a fondo.

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
