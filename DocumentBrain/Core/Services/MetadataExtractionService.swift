import Foundation

/// Calls the Cloudflare Worker to extract structured metadata from document text.
/// Uses Gemini with a strict JSON-only prompt. Fails silently — metadata is
/// always optional enrichment, never a required step.
struct MetadataExtractionService {

    // MARK: - Config (same plist as GeminiQAProvider)

    private static let config: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return [:] }
        return dict
    }()

    private static var workerURL: String {
        (config["WorkerURL"] as? String) ?? ""
    }

    private static var appSecret: String {
        (config["AppSecret"] as? String) ?? ""
    }

    // MARK: - Public API

    /// Returns `nil` if the document has no financial/structured content worth extracting.
    func extract(from text: String, documentTitle: String) async -> StructuredDocumentData? {
        guard !Self.workerURL.isEmpty else { return nil }

        let prompt = buildPrompt(text: text, title: documentTitle)

        do {
            let raw = try await callWorker(prompt: prompt)
            return parseJSON(from: raw)
        } catch {
            AppLogger.debug("[Metadata] Extraction failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompt

    private func buildPrompt(text: String, title: String) -> String {
        let truncated = String(text.prefix(3000))
        return """
        Analiza el siguiente documento y extrae datos estructurados si es relevante (factura, recibo, contrato, nómina, ticket, presupuesto, extracto bancario u otro documento con datos concretos).

        Si el documento NO contiene datos estructurados relevantes (es un artículo de opinión, un libro, una nota sin datos económicos, etc.), responde con:
        {"isEmpty": true}

        Si SÍ tiene datos estructurados, responde ÚNICAMENTE con JSON válido sin texto adicional ni bloques de código:
        {
          "documentType": "factura|recibo|contrato|nómina|extracto|ticket|presupuesto|otro",
          "vendor": "nombre del emisor, comercio o empresa (null si no aparece)",
          "date": "YYYY-MM-DD (null si no aparece)",
          "amount": número decimal sin símbolo de moneda (null si no aparece),
          "currency": "EUR|USD|GBP|etc (null si no aparece o no es relevante)",
          "category": "alimentación|transporte|salud|educación|entretenimiento|hogar|trabajo|finanzas|compras|suministros|viajes|otro"
        }

        Título del documento: \(title)

        Texto:
        \(truncated)
        """
    }

    // MARK: - Worker call

    private func callWorker(prompt: String) async throws -> String {
        guard let url = URL(string: Self.workerURL + "/chat") else {
            throw MetadataError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(Self.appSecret, forHTTPHeaderField: "x-app-secret")
        request.timeoutInterval = 20

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": "You are a JSON extraction API. You MUST respond with ONLY a valid JSON object. No explanations, no markdown, no prose. Only JSON."]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "maxOutputTokens": 1024,
                "temperature": 0.0
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw MetadataError.httpError
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            AppLogger.debug("[Metadata] HTTP \(http.statusCode): \(body.prefix(300))")
            throw MetadataError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw MetadataError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON parsing

    private func parseJSON(from raw: String) -> StructuredDocumentData? {
        // Try several extraction strategies in order of precision
        let cleaned: String
        if let extracted = extractJSONObject(raw) {
            cleaned = extracted
        } else {
            cleaned = stripCodeFences(raw)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLogger.debug("[Metadata] Cannot parse JSON: \(raw.prefix(200))")
            return nil
        }

        // Model returned isEmpty signal
        if json["isEmpty"] as? Bool == true {
            return nil
        }

        var result = StructuredDocumentData()

        if let raw = json["documentType"] as? String {
            result.documentType = StructuredDocumentData.DocumentType(rawValue: raw)
        }
        if let vendor = json["vendor"] as? String, vendor != "null", !vendor.isEmpty {
            result.vendor = vendor
        }
        if let date = json["date"] as? String, date != "null", !date.isEmpty {
            result.date = date
        }
        if let amount = json["amount"] as? Double {
            result.amount = amount
        } else if let amount = json["amount"] as? Int {
            result.amount = Double(amount)
        }
        if let currency = json["currency"] as? String, currency != "null", !currency.isEmpty {
            result.currency = currency.uppercased()
        }
        if let raw = json["category"] as? String {
            result.category = StructuredDocumentData.Category(rawValue: raw)
        }

        return result.isEmpty ? nil : result
    }

    /// Finds the outermost `{…}` block within any surrounding prose or code fences.
    /// Does NOT pre-validate — the caller's JSONSerialization call handles that.
    private func extractJSONObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(text[start...end])
    }

    private func stripCodeFences(_ text: String) -> String {
        var s = text
        // Handle optional newline after opening fence
        for prefix in ["```json\n", "```JSON\n", "```\n", "```json", "```JSON", "```"] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        // Handle optional newline before closing fence
        if s.hasSuffix("\n```") { s = String(s.dropLast(4)) }
        else if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

private enum MetadataError: Error {
    case invalidURL
    case httpError
    case parseError
}
