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

    Amount sign rules:
    - Expense (negative): bought, spent, paid, cost, purchase, ordered, subscribed, charged
    - Income (positive): received, got, earned, salary, income, profit, refund, gave me, sent me, transferred to me, from [person/source]
    - Ambiguous with no income signal → treat as expense

    Description rules:
    - Always set a short English description (1-3 words). NEVER return null for description on a transaction.
    - Use the item/purpose: "taxi", "salary", "coffee", "from mom"
    - If no clear item, use the person/source: "from mother", "from friend"
    - Last resort fallback: "income" for positive, "expense" for negative

    Currency rules:
    - $ or USD → "USD"
    - € or EUR → "EUR"
    - £ or GBP → "GBP"
    - ₽ or rub → "RUB"
    - tmt, manat, m → "TMT"
    - Default to TMT if no currency mentioned

    Category rules:
    - transfer: ONLY when moving between user's own accounts/wallets ("moved to savings", "topped up card")
    - salary: regular paycheck or wage
    - other: gifts, money from family/friends, any income where source is a person
    - Never use transfer just because a person is the source of income

    Query rules:
    - "show", "see", "how much", "list", "display", "what did I", "total" → query intent
    - Default queryPeriod to "month" if not specified

    Language: user may write in English, Russian, or Turkmen — parse correctly regardless.

    Examples:
    "i received 200$ from my mother" → {"intent":"transaction","amount":200,"currency":"USD","description":"from mother","category":"other",...}
    "spent 50 tmt on taxi" → {"intent":"transaction","amount":-50,"currency":"TMT","description":"taxi","category":"transport",...}
    "salary 3000" → {"intent":"transaction","amount":3000,"currency":"TMT","description":"salary","category":"salary",...}
    "show food expenses this month" → {"intent":"query","queryCategory":"food","queryType":"expense","queryPeriod":"month",...}
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

        let cleaned = Self.firstJSONObject(in: stripped) ?? stripped

        guard let jsonData = cleaned.data(using: .utf8) else { throw ParserError.decodingFailed }
        return try JSONDecoder().decode(ParsedInput.self, from: jsonData)
    }

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
