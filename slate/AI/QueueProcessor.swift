import SwiftData
import Network
import Foundation

@MainActor
final class QueueProcessor {

    private let parser: any InputParserProtocol
    private let modelContext: ModelContext

    init(parser: any InputParserProtocol, modelContext: ModelContext) {
        self.parser = parser
        self.modelContext = modelContext
    }

    func flushQueue() async {
        let pendingStatus = PendingInput.Status.pending.rawValue
        let descriptor = FetchDescriptor<PendingInput>(
            predicate: #Predicate { $0.statusRaw == pendingStatus },
            sortBy: [SortDescriptor(\.entryDate)]
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }

        for item in pending {
            do {
                let parsed = try await parser.parse(input: item.rawText)
                if let tx = makeTransaction(from: parsed, raw: item.rawText, date: item.entryDate) {
                    modelContext.insert(tx)
                    modelContext.delete(item)
                } else {
                    item.retryCount += 1
                    item.status = .failed
                }
            } catch {
                item.retryCount += 1
                item.status = .failed
            }
        }

        try? modelContext.save()
    }

    private func makeTransaction(from parsed: ParsedInput, raw: String, date: Date) -> Transaction? {
        guard parsed.intent == .transaction,
              let amount = parsed.amount,
              let currency = parsed.currency,
              let description = parsed.description else {
            return nil
        }
        return Transaction(
            amount: amount,
            currency: currency,
            desc: description,
            category: parsed.category ?? .other,
            rawInput: raw,
            date: date
        )
    }
}
