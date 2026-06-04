import SwiftData
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

    let networkMonitor: NetworkMonitor
    let speechRecognizer: SpeechRecognizer
    private let parser: any InputParserProtocol
    private var queueProcessor: QueueProcessor?

    init() {
        print("[Slate] InputViewModel.init start — thread: \(Thread.isMainThread ? "main" : "bg")")
        let t = Date()
        networkMonitor = NetworkMonitor()
        print("[Slate] NetworkMonitor created: \(Date().timeIntervalSince(t))s")
        speechRecognizer = SpeechRecognizer()
        print("[Slate] SpeechRecognizer created: \(Date().timeIntervalSince(t))s")
        parser = ParserFactory.make()
        print("[Slate] Parser created: \(Date().timeIntervalSince(t))s")
        print("[Slate] InputViewModel.init done")
    }

    func setup(modelContext: ModelContext) {
        print("[Slate] setup() called")
        guard queueProcessor == nil else { return }
        let processor = QueueProcessor(parser: parser, modelContext: modelContext)
        queueProcessor = processor
        networkMonitor.onConnectionRestored = { [weak processor] in
            Task { await processor?.flushQueue() }
        }
        print("[Slate] setup() done")
    }

    func submit(modelContext: ModelContext) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }
        speechRecognizer.stop()

        errorMessage = nil
        isProcessing = true
        defer { isProcessing = false }

        print("[Slate] Submit: \"\(text)\" | connected: \(networkMonitor.isConnected)")

        if networkMonitor.isConnected {
            do {
                print("[Slate] Parsing via cloud...")
                let parsed = try await parser.parse(input: text)
                print("[Slate] Parsed: intent=\(parsed.intent), amount=\(String(describing: parsed.amount)), currency=\(String(describing: parsed.currency)), desc=\(String(describing: parsed.description))")
                if let tx = makeTransaction(from: parsed, raw: text) {
                    modelContext.insert(tx)
                    try? modelContext.save()
                    inputText = ""
                    let sign = tx.amount >= 0 ? "+" : ""
                    print("[Slate] Saved transaction: \(sign)\(formatAmount(tx.amount)) \(tx.currency) · \(tx.desc)")
                    showToast("\(sign)\(formatAmount(tx.amount)) \(tx.currency) · \(tx.desc)")
                } else if parsed.intent == .query {
                    inputText = ""
                    showToast("Query support coming soon")
                } else {
                    print("[Slate] Parse result not actionable")
                    errorMessage = "Didn't understand — try: -50 tmt taxi"
                }
            } catch {
                print("[Slate] Parse error: \(error)")
                errorMessage = "Didn't understand — try: -50 tmt taxi"
            }
        } else {
            print("[Slate] Offline — queuing input")
            let pending = PendingInput(rawText: text)
            modelContext.insert(pending)
            try? modelContext.save()
            inputText = ""
            showToast("Saved — will process when back online")
        }
    }

    func retryFailed(_ item: PendingInput, modelContext: ModelContext) async {
        item.status = .pending
        item.retryCount = 0
        try? modelContext.save()
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
              let currency = parsed.currency,
              let description = parsed.description else { return nil }
        return Transaction(
            amount: amount,
            currency: currency,
            desc: description,
            category: parsed.category ?? .other,
            rawInput: raw
        )
    }

    private func formatAmount(_ amount: Double) -> String {
        if amount == amount.rounded() {
            return String(Int(amount))
        }
        return String(format: "%.2f", amount)
    }
}
