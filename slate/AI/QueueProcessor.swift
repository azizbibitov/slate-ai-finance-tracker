import Foundation

@MainActor
final class QueueProcessor {

    private let parser: any InputParserProtocol
    private let storage: any StorageRepository

    init(parser: any InputParserProtocol, storage: any StorageRepository) {
        self.parser = parser
        self.storage = storage
    }

    func flushQueue() async {
        let pending = storage.fetchPending()
        guard !pending.isEmpty else { return }

        let context = ParserContext(accounts: storage.fetchAllAccounts().map {
            ParserContext.AccountInfo(name: $0.name, currency: $0.currency, isDefault: $0.isDefault)
        })

        for item in pending {
            do {
                let parsed = try await parser.parse(input: item.rawText, context: context)
                if let tx = makeTransaction(from: parsed, raw: item.rawText, date: item.entryDate) {
                    storage.insertTransaction(tx)
                    storage.deletePending(item)
                } else {
                    item.retryCount += 1
                    item.status = .failed
                }
            } catch {
                item.retryCount += 1
                item.status = .failed
            }
        }

        try? storage.save()
    }

    private func makeTransaction(from parsed: ParsedInput, raw: String, date: Date) -> Transaction? {
        guard parsed.intent == .transaction,
              let amount = parsed.amount,
              let currency = parsed.currency else { return nil }
        return Transaction(
            amount: amount,
            currency: currency,
            desc: parsed.description ?? (amount >= 0 ? "income" : "expense"),
            category: parsed.category ?? .other,
            rawInput: raw,
            date: date
        )
    }
}
