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
      "intent": "transaction" | "query" | "transfer" | "createAccount",
      "amount": number | null,
      "currency": string | null,
      "description": string | null,
      "category": string | null,
      "queryCategory": string | null,
      "queryType": "income" | "expense" | "accounts" | null,
      "queryPeriod": "today" | "yesterday" | "week" | "month" | "year" | "all" | null,
      "querySearch": string | null,
      "sourceAccount": string | null,
      "destinationAccount": string | null,
      "exchangeRate": number | null,
      "destinationAmount": number | null,
      "accountName": string | null,
      "accountCurrency": string | null,
      "accountEmoji": string | null
    }

    Intent rules:
    - "transaction": a regular income or expense
    - "transfer": moving money between accounts ("transferred", "moved", "sent to my card/wallet")
    - "createAccount": creating a new wallet or account ("I have a cash wallet", "create savings", "add card")
    - "switchAccount": switching the active wallet ("switch to dollar wallet", "use cash", "set card as main", "activate savings")
    - "query": asking about history or balances
    - "unknown": anything that is NOT financial — commands, random text, questions unrelated to money. When in doubt, use "unknown".

    Amount sign rules (transaction only):
    - Expense (negative): bought, spent, paid, cost, purchase, ordered, subscribed, charged
    - Income (positive): + prefix on amount, received, got, earned, salary, income, profit, refund, gave me, sent me, from [person], freelance platform names
    - Ambiguous with no income signal → treat as expense

    Description rules:
    - Always set a short English description (1-3 words). NEVER return null for description on a transaction.
    - Use the item/purpose: "taxi", "salary", "coffee", "from mom"
    - Last resort fallback: "income" for positive, "expense" for negative

    Currency rules:
    - $ or USD → "USD"; € or EUR → "EUR"; £ or GBP → "GBP"; ₽ or rub → "RUB"; tmt/manat → "TMT"
    - Default to TMT if no currency mentioned

    Category rules:
    - If the user explicitly names a category (e.g. "category food", "it's entertainment", "mark as health"), use that category.
    - Otherwise pick the best fit from: food, transport, salary, shopping, health, utilities, entertainment, rent, transfer, other
    - food: anything edible or drinkable — groceries, restaurants, cafes, coffee, water (drink/bottle), sushi, pizza, food delivery (wolt, glovo, etc.), snacks
    - utilities: recurring bills — electricity, gas, water BILL, internet, phone plan, AI tools (claude, chatgpt), software subscriptions
    - salary: wages, freelance platforms (upwork, fiverr, toptal, freelancer), any job/work income
    - entertainment: streaming (netflix, spotify), games, movies, hobbies
    - transfer: ONLY for same-account movements, never for person-to-person income
    - other: gifts, money from family/friends, anything that doesn't fit above

    Transfer rules:
    - amount: always the source amount (positive number)
    - currency: source currency
    - sourceAccount/destinationAccount: account names as user stated them (or null)
    - For cross-currency: set exchangeRate if user says "at 19.4" / "1$=19.4" / "rate was 19.4"
    - Set destinationAmount if user states it directly ("got 1940 tmt")

    createAccount rules:
    - accountName: name as stated ("Cash", "Kapitalbank", "Dollar savings")
    - accountCurrency: detected from name or context
    - accountEmoji: pick a fitting emoji (💵 USD, 💳 card, 💰 cash, 🏦 bank, 💴 TMT/RUB)
    - amount: opening balance if mentioned (positive)

    Query rules:
    - "show accounts"/"show wallets"/"my balances" → queryType: "accounts"
    - Default queryPeriod to "month" if not specified
    - querySearch: extract any person name, place, or keyword the user wants to filter by
      e.g. "expenses for [name]" → querySearch: "[name]"
      e.g. "taxi spending this week" → querySearch: "taxi"
      e.g. "what did I spend at Berkarar" → querySearch: "berkarar"
      Set to lowercase. Null if no specific keyword.

    Language: English, Russian, or Turkmen — parse correctly regardless.

    Examples:
    "i received 200$ from my mother" → {"intent":"transaction","amount":200,"currency":"USD","description":"from mother","category":"other"}
    "+500$ upwork" → {"intent":"transaction","amount":500,"currency":"USD","description":"upwork","category":"salary"}
    "spent 50 tmt on taxi" → {"intent":"transaction","amount":-50,"currency":"TMT","description":"taxi","category":"transport"}
    "transferred 100$ to tmt wallet at rate 19.4" → {"intent":"transfer","amount":100,"currency":"USD","destinationAccount":"tmt wallet","exchangeRate":19.4}
    "moved 100 dollars to manat card, got 1940 tmt" → {"intent":"transfer","amount":100,"currency":"USD","destinationAccount":"manat card","destinationAmount":1940}
    "transferred 100$ to tmt wallet, it was 1$=19.4" → {"intent":"transfer","amount":100,"currency":"USD","destinationAccount":"tmt wallet","exchangeRate":19.4}
    "I have a cash wallet with 5000 tmt" → {"intent":"createAccount","accountName":"Cash","accountCurrency":"TMT","accountEmoji":"💰","amount":5000}
    "create dollar savings account" → {"intent":"createAccount","accountName":"Dollar savings","accountCurrency":"USD","accountEmoji":"💵"}
    "show accounts" → {"intent":"query","queryType":"accounts"}
    "switch to dollar wallet" → {"intent":"switchAccount","sourceAccount":"dollar wallet"}
    "use cash" → {"intent":"switchAccount","sourceAccount":"cash"}
    "show food expenses this month" → {"intent":"query","queryCategory":"food","queryType":"expense","queryPeriod":"month"}
    """

    func parse(input: String, context: ParserContext) async throws -> ParsedInput {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt + contextSection(context)],
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

        var cleaned = Self.firstJSONObject(in: stripped) ?? stripped
        // JSON spec forbids +number; LLMs sometimes emit it for positive amounts
        cleaned = Self.stripLeadingPlusFromNumbers(in: cleaned)
        print("[DEBUG] raw JSON: \(cleaned)")

        guard let jsonData = cleaned.data(using: .utf8) else { throw ParserError.decodingFailed }
        return try JSONDecoder().decode(ParsedInput.self, from: jsonData)
    }

    private func contextSection(_ context: ParserContext) -> String {
        guard !context.accounts.isEmpty else { return "" }
        let lines = context.accounts.map { a in
            "- \(a.name) (\(a.currency))\(a.isDefault ? " [active wallet]" : "")"
        }
        return "\n\nUser's current wallets:\n" + lines.joined(separator: "\n")
            + "\nMatch sourceAccount/destinationAccount to these exact names when the user references a wallet."
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

    // Replace patterns like `: +500` with `: 500` — JSON forbids leading + on numbers.
    static func stripLeadingPlusFromNumbers(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(:\s*)\+(\d)"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1$2")
    }
}

private struct OpenAICompatibleResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
