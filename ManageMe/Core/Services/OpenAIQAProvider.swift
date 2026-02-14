import Foundation
import Security

/// Q&A provider using OpenAI's Chat Completions API
/// Used as a silent fallback when Apple Intelligence is unavailable
final class OpenAIQAProvider: QAProvider {
    var name: String { "Asistente inteligente" }
    var kind: QAProviderKind { .cloud }

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    private var apiKey: String {
        APIKeyStore.loadOpenAIKey()
    }

    private let model = "gpt-4o-mini"
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func answer(query: String, context: [SearchResult]) async throws -> String {
        guard isAvailable else { throw QAError.noProviderAvailable }

        let userMessage = QAService.buildPrompt(query: query, context: Array(context.prefix(3)))

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 300,
            "temperature": 0.2
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QAError.apiError("Respuesta no válida")
        }

        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw QAError.apiError(message)
            }
            throw QAError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw QAError.apiError("No se pudo leer la respuesta")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum APIKeyStore {
    private static let service = "com.manageme.app"
    private static let account = "openai_api_key"
    private static let legacyUserDefaultsKey = "openai_api_key"

    static func migrateLegacyUserDefaultsKeyIfNeeded() {
        let existing = loadOpenAIKey()
        guard existing.isEmpty else { return }

        guard let legacy = UserDefaults.standard.string(forKey: legacyUserDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty else { return }

        try? saveOpenAIKey(legacy)
        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey)
    }

    static func loadOpenAIKey() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return "" }
        guard let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func saveOpenAIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try deleteOpenAIKey()
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if status == errSecItemNotFound {
            var addQuery = baseQuery
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

    static func deleteOpenAIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
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
