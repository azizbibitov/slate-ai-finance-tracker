import Foundation

final class GeminiInputParser: InputParserProtocol {

    private let apiKey: String
    private let model = "gemini-1.5-flash"

    init(apiKey: String = Secrets.geminiKey) {
        self.apiKey = apiKey
    }

    private let systemPrompt = """
    You are a financial input parser for a personal expense tracker called Slate.
    Parse the user's message and return ONLY a JSON object. No explanation, no markdown.

    JSON schema:
    {
      "intent": "transaction" | "query",
      "amount": number | null,
      "currency": string | null,
      "description": string | null,
      "category": string | null,
      "queryCategory": string | null,
      "queryType": "income" | "expense" | null,
      "queryPeriod": "today" | "week" | "month" | "year" | "all" | null
    }

    Rules:
    - "bought", "spent", "paid", "cost" → negative amount (expense)
    - "received", "salary", "earned", "got paid" → positive amount (income)
    - If sign is ambiguous and no income word present → treat as expense
    - "show", "see", "how much", "list", "display" → query intent
    - Default queryPeriod to "month" if not specified
    - User may write in English, Russian, or Turkmen — parse correctly regardless
    - Default currency to TMT if not specified
    - Return null for fields you cannot determine
    """

    func parse(input: String) async throws -> ParsedInput {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw ParserError.apiError }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [
                ["parts": [["text": input]]]
            ],
            "generationConfig": [
                "temperature": 0,
                "maxOutputTokens": 200
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw ParserError.apiError }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[Slate] Gemini API error \(http.statusCode): \(body)")
            throw ParserError.apiError
        }

        let json = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let content = json.candidates.first?.content.parts.first?.text else {
            throw ParserError.emptyResponse
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        guard let jsonData = cleaned.data(using: .utf8) else { throw ParserError.decodingFailed }
        return try JSONDecoder().decode(ParsedInput.self, from: jsonData)
    }
}

private struct GeminiResponse: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            struct Part: Codable { let text: String }
            let parts: [Part]
        }
        let content: Content
    }
    let candidates: [Candidate]
}
