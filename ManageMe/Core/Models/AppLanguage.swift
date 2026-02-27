import Foundation

/// Supported app languages. Persisted in UserDefaults.
enum AppLanguage: String, CaseIterable, Identifiable {
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    /// Display name shown in the language selector (always in its own language)
    var displayName: String {
        switch self {
        case .spanish: return "Español"
        case .english: return "English"
        }
    }

    /// Flag emoji for visual identification
    var flag: String {
        switch self {
        case .spanish: return "🇪🇸"
        case .english: return "🇬🇧"
        }
    }

    // MARK: - Persistence

    private static let key = "app_language"

    /// Current app language. Defaults to Spanish.
    static var current: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let lang = AppLanguage(rawValue: raw) else {
                return .spanish
            }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    // MARK: - LLM Prompt Strings

    /// System prompt for the LLM (Gemini / Apple Intelligence)
    var systemPrompt: String {
        switch self {
        case .spanish:
            return """
            Eres un asistente personal que responde preguntas basándose ÚNICAMENTE en los documentos del usuario.

            REGLAS:
            - Responde SOLO con información que aparezca en los fragmentos proporcionados.
            - Si los fragmentos NO contienen información relevante, responde EXACTAMENTE: "\(noInfoFound)"
            - NO inventes ni supongas información que no esté en los fragmentos.
            - Responde en español.
            - Cita el nombre del documento cuando sea relevante.

            ESTILO DE RESPUESTA:
            - Desarrolla la respuesta con detalle: incluye todos los datos relevantes que encuentres (fechas, nombres, tecnologías, responsabilidades, cantidades, etc.)
            - Organiza la información de forma clara usando párrafos, listas o secciones según convenga.
            - Si hay información distribuida en varios fragmentos del mismo documento, sintetízala en una respuesta coherente y completa.
            - No te limites a una línea; elabora una respuesta completa que responda la pregunta del usuario a fondo.
            """
        case .english:
            return """
            You are a personal assistant that answers questions based ONLY on the user's documents.

            RULES:
            - Answer ONLY with information that appears in the provided snippets.
            - If the snippets do NOT contain relevant information, reply EXACTLY: "\(noInfoFound)"
            - NEVER invent or guess information not in the snippets.
            - Reply in English.
            - Cite the document name when relevant.

            RESPONSE STYLE:
            - Provide detailed, thorough answers: include all relevant data you find (dates, names, technologies, responsibilities, amounts, etc.)
            - Organize information clearly using paragraphs, bullet points, or sections as appropriate.
            - If information is spread across multiple snippets from the same document, synthesize it into one coherent, complete answer.
            - Don't limit yourself to one line; elaborate fully to answer the user's question thoroughly.
            """
        }
    }

    /// Prompt wrapper for document snippets
    var snippetsHeader: String {
        switch self {
        case .spanish: return "FRAGMENTOS DE DOCUMENTOS:"
        case .english: return "DOCUMENT SNIPPETS:"
        }
    }

    /// Label for each snippet
    func snippetLabel(title: String, index: Int) -> String {
        switch self {
        case .spanish: return "--- Documento: \(title) (fragmento \(index)) ---"
        case .english: return "--- Document: \(title) (snippet \(index)) ---"
        }
    }

    var questionLabel: String {
        switch self {
        case .spanish: return "PREGUNTA"
        case .english: return "QUESTION"
        }
    }

    // MARK: - UI Strings

    var noInfoFound: String {
        switch self {
        case .spanish: return "No encontré información sobre esto en tus documentos."
        case .english: return "I didn't find information about this in your documents."
        }
    }

    var noRelevantResults: String {
        switch self {
        case .spanish: return "No encontré información relevante en tus documentos. Prueba con otra pregunta o importa más archivos."
        case .english: return "I didn't find relevant information in your documents. Try another question or import more files."
        }
    }

    var embeddingsUnavailable: String {
        switch self {
        case .spanish: return "El modelo de embeddings no está disponible. Asegúrate de que MiniLM está incluido en el proyecto."
        case .english: return "The embedding model is not available. Make sure MiniLM is included in the project."
        }
    }

    // Settings
    var settingsTitle: String {
        switch self { case .spanish: return "Ajustes"; case .english: return "Settings" }
    }
    var aiSectionTitle: String {
        switch self { case .spanish: return "Inteligencia Artificial"; case .english: return "Artificial Intelligence" }
    }
    var storageSectionTitle: String {
        switch self { case .spanish: return "Almacenamiento"; case .english: return "Storage" }
    }
    var actionsSectionTitle: String {
        switch self { case .spanish: return "Acciones"; case .english: return "Actions" }
    }
    var aboutSectionTitle: String {
        switch self { case .spanish: return "Acerca de"; case .english: return "About" }
    }
    var languageSectionTitle: String {
        switch self { case .spanish: return "Idioma"; case .english: return "Language" }
    }
    var documentsLabel: String {
        switch self { case .spanish: return "Documentos"; case .english: return "Documents" }
    }
    var storageUsedLabel: String {
        switch self { case .spanish: return "Espacio usado"; case .english: return "Storage used" }
    }
    var reindexLabel: String {
        switch self { case .spanish: return "Reindexar documentos"; case .english: return "Reindex documents" }
    }
    var deleteAllLabel: String {
        switch self { case .spanish: return "Borrar todos los datos"; case .english: return "Delete all data" }
    }
    var deleteAllTitle: String {
        switch self { case .spanish: return "Borrar todos los datos"; case .english: return "Delete all data" }
    }
    var deleteAllMessage: String {
        switch self {
        case .spanish: return "Se eliminarán todos los documentos y datos. Esta acción no se puede deshacer."
        case .english: return "All documents and data will be deleted. This action cannot be undone."
        }
    }
    var cancelButton: String {
        switch self { case .spanish: return "Cancelar"; case .english: return "Cancel" }
    }
    var deleteButton: String {
        switch self { case .spanish: return "Borrar todo"; case .english: return "Delete all" }
    }
    var versionLabel: String {
        switch self { case .spanish: return "Versión"; case .english: return "Version" }
    }
    var tagline: String {
        switch self { case .spanish: return "ManageMe — Tu segundo cerebro digital"; case .english: return "ManageMe — Your digital second brain" }
    }

    // AI status
    var aiActiveOnDevice: String {
        switch self { case .spanish: return "Activo — en tu dispositivo"; case .english: return "Active — on your device" }
    }
    var aiActiveCloud: String {
        switch self { case .spanish: return "Activo — asistente inteligente"; case .english: return "Active — smart assistant" }
    }
    var aiBasicMode: String {
        switch self { case .spanish: return "Modo básico"; case .english: return "Basic mode" }
    }
    var aiFooterOnDevice: String {
        switch self {
        case .spanish: return "Las respuestas se procesan en tu dispositivo. Privado y sin coste."
        case .english: return "Responses are processed on your device. Private and free."
        }
    }
    var aiFooterCloud: String {
        switch self {
        case .spanish: return "Las respuestas se generan con inteligencia artificial. Requiere conexión a internet."
        case .english: return "Responses are generated with AI. Requires internet connection."
        }
    }
    var aiFooterBasic: String {
        switch self {
        case .spanish: return "Las respuestas se extraen directamente de tus documentos."
        case .english: return "Responses are extracted directly from your documents."
        }
    }

    // iCloud
    var iCloudTitle: String {
        switch self { case .spanish: return "Sincronización iCloud"; case .english: return "iCloud Sync" }
    }
    var iCloudSyncing: String {
        switch self { case .spanish: return "Sincronizando..."; case .english: return "Syncing..." }
    }
    var iCloudActive: String {
        switch self { case .spanish: return "Activa"; case .english: return "Active" }
    }
    var iCloudUnavailable: String {
        switch self { case .spanish: return "No disponible"; case .english: return "Not available" }
    }
    var iCloudFooter: String {
        switch self {
        case .spanish: return "Documentos, carpetas y conversaciones se sincronizan automáticamente entre tus dispositivos."
        case .english: return "Documents, folders, and conversations sync automatically across your devices."
        }
    }

    // Chat
    var chatPlaceholder: String {
        switch self { case .spanish: return "Pregunta sobre tus documentos..."; case .english: return "Ask about your documents..." }
    }
    var chatEmptyTitle: String {
        switch self { case .spanish: return "Tu segundo cerebro"; case .english: return "Your second brain" }
    }
    var chatEmptySubtitle: String {
        switch self {
        case .spanish: return "Pregunta cualquier cosa sobre tus documentos importados"
        case .english: return "Ask anything about your imported documents"
        }
    }

    // Extractive answer labels
    func extractiveHeader(docTitle: String, entityName: String) -> String {
        switch self {
        case .spanish: return "Según **\(docTitle)**, esta es la información que encontré sobre \(entityName):"
        case .english: return "According to **\(docTitle)**, here's what I found about \(entityName):"
        }
    }
    func extractiveMultiHeader(entityName: String, count: Int) -> String {
        switch self {
        case .spanish: return "Encontré información sobre \(entityName) en \(count) documentos:"
        case .english: return "I found information about \(entityName) in \(count) documents:"
        }
    }
}
