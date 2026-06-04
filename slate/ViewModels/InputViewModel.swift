import Foundation

struct ToastMessage: Equatable {
    let text: String
    var isError: Bool = false
}

@Observable
@MainActor
final class InputViewModel {
    var inputText = ""
    var isProcessing = false
    var toast: ToastMessage?
    var errorMessage: String?
    var queryResult: QueryResult?

    let networkMonitor: NetworkMonitor
    let speechRecognizer: any SpeechRecognizerProtocol
    private let parser: any InputParserProtocol
    private var storage: (any StorageRepository)?
    private var queueProcessor: QueueProcessor?

    init() {
        networkMonitor = NetworkMonitor()
        speechRecognizer = SpeechRecognizer()
        parser = ParserFactory.make()
    }

    func setup(storage: any StorageRepository) {
        guard queueProcessor == nil else { return }
        self.storage = storage
        let processor = QueueProcessor(parser: parser, storage: storage)
        queueProcessor = processor
        networkMonitor.onConnectionRestored = { [weak processor] in
            Task { await processor?.flushQueue() }
        }
    }

    func submit() async {
        guard let storage else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        speechRecognizer.stop()
        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        if networkMonitor.isConnected {
            do {
                let parsed = try await parser.parse(input: text)
                if let tx = makeTransaction(from: parsed, raw: text) {
                    storage.insertTransaction(tx)
                    try? storage.save()
                    inputText = ""
                    let amountStr = CurrencyFormatter.format(tx.amount, showSign: true)
                    showToast("\(amountStr) \(tx.currency) · \(tx.desc)")
                } else if parsed.intent == .query {
                    let allTransactions = storage.fetchAllTransactions()
                    queryResult = QueryFilter.run(query: parsed, transactions: allTransactions, originalText: text)
                    inputText = ""
                } else {
                    errorMessage = "Didn't understand — try: -50 tmt taxi"
                }
            } catch {
                errorMessage = "Didn't understand — try: -50 tmt taxi"
            }
        } else {
            let pending = PendingInput(rawText: text)
            storage.insertPending(pending)
            try? storage.save()
            inputText = ""
            showToast("Saved — will process when back online")
        }
    }

    func retryFailed(_ item: PendingInput) async {
        item.status = .pending
        item.retryCount = 0
        try? storage?.save()
        await queueProcessor?.flushQueue()
    }

    private func showToast(_ text: String, isError: Bool = false) {
        toast = ToastMessage(text: text, isError: isError)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.text == text { toast = nil }
        }
    }

    private func makeTransaction(from parsed: ParsedInput, raw: String) -> Transaction? {
        guard parsed.intent == .transaction,
              let amount = parsed.amount,
              let currency = parsed.currency else { return nil }
        return Transaction(
            amount: amount,
            currency: currency,
            desc: parsed.description ?? (amount >= 0 ? "income" : "expense"),
            category: parsed.category ?? .other,
            rawInput: raw
        )
    }

}
