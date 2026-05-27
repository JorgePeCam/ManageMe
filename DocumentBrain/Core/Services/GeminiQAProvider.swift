import Foundation
import Security

/// Q&A provider using Google Gemini API (free tier)
/// Used as the primary cloud provider — free, no cost to developer or user.
/// Includes per-device daily rate limiting to protect the shared API quota.
final class GeminiQAProvider: StreamableQAProvider {
    var name: String { "Asistente inteligente" }
    var kind: QAProviderKind { .cloud }

    /// Max cloud queries per device per day.
    /// With 250 RPD free tier and this limit, supports ~12+ active users.
    /// When exhausted, the app falls back gracefully to extractive answers.
    static let dailyLimitPerDevice = 20

    var isAvailable: Bool {
        !apiKey.isEmpty && !DailyUsageTracker.isLimitReached(limit: Self.dailyLimitPerDevice)
    }

    /// Remaining cloud queries for today on this device
    var remainingQueries: Int {
        max(0, Self.dailyLimitPerDevice - DailyUsageTracker.todayCount)
    }

    private var apiKey: String {
        APIKeyStore.loadKey()
    }

    // MARK: - Key Verification

    /// Makes a minimal test call to verify a Gemini API key is valid.
    static func verifyKey(_ key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Use gemini-1.5-flash for verification — stable free-tier model that
        // handles minimal prompts without thinking-token requirements.
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(trimmed)") else { return false }

        let body: [String: Any] = [
            "contents": [["parts": [["text": "Hi"]]]],
            "generationConfig": ["maxOutputTokens": 10]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }

        // 200 = valid key and successful response
        // 400 = bad request but key was accepted (treat as valid)
        // 403 = invalid or revoked key
        return http.statusCode != 403
    }

    // MARK: - Multi-turn builder

    /// Builds the Gemini `contents` array: history turns + current user message.
    private func buildContents(history: [ConversationTurn], currentPrompt: String) -> [[String: Any]] {
        var contents: [[String: Any]] = []
        for turn in history {
            contents.append(["role": "user",  "parts": [["text": turn.userMessage]]])
            contents.append(["role": "model", "parts": [["text": turn.assistantMessage]]])
        }
        contents.append(["role": "user", "parts": [["text": currentPrompt]]])
        return contents
    }

    // MARK: - Gemini API

    private let model = "gemini-2.5-flash"

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
    }

    private var streamEndpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)")!
    }

    func answer(query: String, context: [SearchResult], history: [ConversationTurn] = []) async throws -> String {
        let keyPreview = String(apiKey.prefix(10)) + "..."
        AppLogger.debug("[Gemini] 🚀 Starting request. Key=\(keyPreview) model=\(model) isAvailable=\(isAvailable)")

        guard !apiKey.isEmpty else {
            AppLogger.debug("[Gemini] ❌ API key is empty")
            throw QAError.noProviderAvailable
        }

        if DailyUsageTracker.isLimitReached(limit: Self.dailyLimitPerDevice) {
            AppLogger.debug("[Gemini] ❌ Daily limit reached (\(Self.dailyLimitPerDevice)). Falling back.")
            throw QAError.noProviderAvailable
        }

        let contextPrompt = QAService.buildContextPrompt(query: query, context: Array(context.prefix(8)))
        AppLogger.debug("[Gemini] Prompt length: \(contextPrompt.count) chars, history turns: \(history.count)")

        let requestBody: [String: Any] = [
            "systemInstruction": ["parts": [["text": AppLanguage.current.systemPrompt]]],
            "contents": buildContents(history: history, currentPrompt: contextPrompt),
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.3
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        AppLogger.debug("[Gemini] 📡 Calling \(model)...")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AppLogger.debug("[Gemini] ❌ Network error: \(error.localizedDescription)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QAError.apiError("Respuesta no válida")
        }

        // Global rate limit hit (too many users) — fall back gracefully
        if httpResponse.statusCode == 429 {
            AppLogger.debug("[Gemini] HTTP 429 — global rate limit. Falling back.")
            throw QAError.noProviderAvailable
        }

        if httpResponse.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
            AppLogger.debug("[Gemini] ❌ HTTP \(httpResponse.statusCode): \(bodyStr.prefix(300))")
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw QAError.apiError(message)
            }
            throw QAError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse Gemini response: { candidates: [{ content: { parts: [{ text: "..." }] } }] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw QAError.apiError("No se pudo leer la respuesta")
        }

        // Success — count this usage
        DailyUsageTracker.increment()
        let remaining = remainingQueries
        AppLogger.debug("[Gemini] ✅ Response OK. Usage today: \(DailyUsageTracker.todayCount)/\(Self.dailyLimitPerDevice) (remaining: \(remaining))")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Streaming

    func streamAnswer(query: String, context: [SearchResult], history: [ConversationTurn] = [], onUpdate: @escaping (String) -> Void) async throws {
        let keyPreview = String(apiKey.prefix(10)) + "..."
        AppLogger.debug("[Gemini] 🚀 Starting STREAM request. Key=\(keyPreview) model=\(model)")

        guard !apiKey.isEmpty else {
            throw QAError.noProviderAvailable
        }

        if DailyUsageTracker.isLimitReached(limit: Self.dailyLimitPerDevice) {
            AppLogger.debug("[Gemini] ❌ Daily limit reached. Falling back.")
            throw QAError.noProviderAvailable
        }

        let contextPrompt = QAService.buildContextPrompt(query: query, context: Array(context.prefix(8)))

        let requestBody: [String: Any] = [
            "systemInstruction": ["parts": [["text": AppLanguage.current.systemPrompt]]],
            "contents": buildContents(history: history, currentPrompt: contextPrompt),
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.3
            ]
        ]

        var request = URLRequest(url: streamEndpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        AppLogger.debug("[Gemini] 📡 Streaming from \(model)...")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QAError.apiError("Respuesta no válida")
        }

        if httpResponse.statusCode == 429 {
            AppLogger.debug("[Gemini] HTTP 429 — global rate limit. Falling back.")
            throw QAError.noProviderAvailable
        }

        guard httpResponse.statusCode == 200 else {
            AppLogger.debug("[Gemini] ❌ Stream HTTP \(httpResponse.statusCode)")
            throw QAError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse SSE stream: lines prefixed with "data: " containing JSON chunks
        var accumulated = ""

        for try await line in bytes.lines {
            // SSE format: "data: {json}" lines
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard !jsonString.isEmpty else { continue }

            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                continue
            }

            accumulated += text
            onUpdate(accumulated)
        }

        guard !accumulated.isEmpty else {
            throw QAError.apiError("No se recibió contenido en el stream")
        }

        // Success — count usage
        DailyUsageTracker.increment()
        AppLogger.debug("[Gemini] ✅ Stream complete. Length=\(accumulated.count) chars. Usage: \(DailyUsageTracker.todayCount)/\(Self.dailyLimitPerDevice)")
    }
}

// MARK: - Per-Device Daily Usage Tracker

/// Tracks daily API usage per device using UserDefaults.
/// Resets automatically at midnight (local time).
enum DailyUsageTracker {
    private static let countKey = "gemini_daily_count"
    private static let dateKey = "gemini_daily_date"

    /// Today's date string (yyyy-MM-dd) for comparison
    private static var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Number of queries used today on this device
    static var todayCount: Int {
        let stored = UserDefaults.standard.string(forKey: dateKey) ?? ""
        if stored != todayString {
            // New day — reset counter
            return 0
        }
        return UserDefaults.standard.integer(forKey: countKey)
    }

    /// Whether the daily limit has been reached
    static func isLimitReached(limit: Int) -> Bool {
        todayCount >= limit
    }

    /// Record one more API call
    static func increment() {
        let today = todayString
        let stored = UserDefaults.standard.string(forKey: dateKey) ?? ""

        if stored != today {
            // New day — reset
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(1, forKey: countKey)
        } else {
            let current = UserDefaults.standard.integer(forKey: countKey)
            UserDefaults.standard.set(current + 1, forKey: countKey)
        }
    }
}

// MARK: - API Key Store (Keychain)

enum APIKeyStore {
    private static let service = "com.documentbrain.app"
    private static let account = "api_key"
    private static let legacyAccount = "openai_api_key"
    private static let legacyUserDefaultsKey = "openai_api_key"

    static func migrateLegacyUserDefaultsKeyIfNeeded() {
        // Migrate from UserDefaults to Keychain
        let existing = loadKey()
        guard existing.isEmpty else { return }

        // Check legacy UserDefaults
        if let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacy.isEmpty {
            try? saveKey(legacy)
            UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
            return
        }

        // Check legacy Keychain account
        let legacyKey = loadFromKeychain(account: legacyAccount)
        if !legacyKey.isEmpty {
            try? saveKey(legacyKey)
        }
    }

    static func loadKey() -> String {
        loadFromKeychain(account: account)
    }

    // Keep backward-compatible name for existing callers
    static func loadOpenAIKey() -> String {
        loadKey()
    }

    static func saveKey(_ key: String) throws {
        try saveToKeychain(key: key, account: account)
    }

    static func saveOpenAIKey(_ key: String) throws {
        try saveKey(key)
    }

    static func deleteOpenAIKey() throws {
        try deleteFromKeychain(account: account)
    }

    // MARK: - Keychain Helpers

    private static func loadFromKeychain(account: String) -> String {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func saveToKeychain(key: String, account: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteFromKeychain(account: account)
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if status == errSecItemNotFound {
            var addQuery = baseQuery(account: account)
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw APIKeyStoreError.keychainStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private static func deleteFromKeychain(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Accessible only when unlocked, excluded from iCloud/device backups
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }
}

enum APIKeyStoreError: LocalizedError {
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let code):
            return "Error de llavero (\(code))."
        }
    }
}
