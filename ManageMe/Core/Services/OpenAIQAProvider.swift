import Foundation

/// Q&A provider using OpenAI's Chat Completions API
final class OpenAIQAProvider: QAProvider {
    var name: String { "OpenAI GPT" }

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    }

    // Use gpt-4o-mini: fast, cheap, great for this use case
    private let model = "gpt-4o-mini"
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func answer(query: String, context: [SearchResult]) async throws -> String {
        guard isAvailable else { throw QAError.apiKeyMissing }

        let systemPrompt = QAService.buildPrompt(query: query, context: context)

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": query]
            ],
            "max_tokens": 500,
            "temperature": 0.3
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

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
