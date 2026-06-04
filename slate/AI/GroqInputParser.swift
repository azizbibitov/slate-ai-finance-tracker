import Foundation

final class GroqInputParser: InputParserProtocol {

    private let apiKey: String
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let model = "llama-3.1-8b-instant"

    init(apiKey: String = Secrets.groqKey) {
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": input]
            ],
            "temperature": 0,
            "max_tokens": 200
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw ParserError.apiError }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[Slate] Groq API error \(http.statusCode): \(body)")
            throw ParserError.apiError
        }

        let json = try JSONDecoder().decode(OpenAICompatibleResponse.self, from: data)
        guard let content = json.choices.first?.message.content else {
            throw ParserError.emptyResponse
        }

        let stripped = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        // The model sometimes emits two JSON objects for compound inputs — take only the first.
        let cleaned = Self.firstJSONObject(in: stripped) ?? stripped

        guard let jsonData = cleaned.data(using: .utf8) else { throw ParserError.decodingFailed }
        return try JSONDecoder().decode(ParsedInput.self, from: jsonData)
    }
}

extension GroqInputParser {
    // Scan for the first balanced { } block so stray trailing objects are ignored.
    static func firstJSONObject(in text: String) -> String? {
        var depth = 0
        var start: String.Index? = nil
        for idx in text.indices {
            switch text[idx] {
            case "{":
                if depth == 0 { start = idx }
                depth += 1
            case "}":
                depth -= 1
                if depth == 0, let s = start {
                    return String(text[s...idx])
                }
            default: break
            }
        }
        return nil
    }
}

private struct OpenAICompatibleResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
