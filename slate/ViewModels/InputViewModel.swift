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
    var activeSheet: ActiveSheet?

    enum ActiveSheet: Identifiable {
        case accounts
        case results(QueryResult)

        var id: String {
            switch self {
            case .accounts:         return "accounts"
            case .results(let r):   return "results-\(r.id)"
            }
        }
    }

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
                let context = buildContext(storage: storage)
                let parsed = try await parser.parse(input: text, context: context)
                print("[DEBUG] input=\(text) intent=\(parsed.intent) amount=\(String(describing: parsed.amount)) desc=\(String(describing: parsed.description))")
                switch parsed.intent {
                case .transaction:
                    if let tx = makeTransaction(from: parsed, raw: text, storage: storage) {
                        storage.insertTransaction(tx)
                        try? storage.save()
                        inputText = ""
                        showToast("\(CurrencyFormatter.format(tx.amount, showSign: true)) \(tx.currency) · \(tx.desc)")
                    } else {
                        errorMessage = "Didn't understand -try: -50 tmt taxi"
                    }
                case .query:
                    if parsed.queryType == .accounts {
                        inputText = ""
                        activeSheet = .accounts
                    } else {
                        let allTransactions = storage.fetchAllTransactions()
                        activeSheet = .results(QueryFilter.run(query: parsed, transactions: allTransactions, originalText: text))
                        inputText = ""
                    }
                case .transfer:
                    handleTransfer(from: parsed, raw: text, storage: storage)
                case .createAccount:
                    handleCreateAccount(from: parsed, raw: text, storage: storage)
                case .switchAccount:
                    handleSwitchAccount(from: parsed, storage: storage)
                case .unknown:
                    errorMessage = "That doesn't look like a financial entry"
                }
            } catch {
                errorMessage = "Didn't understand - try: -50 tmt taxi"
            }
        } else {
            let pending = PendingInput(rawText: text)
            storage.insertPending(pending)
            try? storage.save()
            inputText = ""
            showToast("Saved -will process when back online")
        }
    }

    func retryFailed(_ item: PendingInput) async {
        item.status = .pending
        item.retryCount = 0
        try? storage?.save()
        await queueProcessor?.flushQueue()
    }

    // MARK: - Account creation

    private func handleCreateAccount(from parsed: ParsedInput, raw: String, storage: any StorageRepository) {
        let accounts = storage.fetchAllAccounts()
        let name = parsed.accountName ?? "Account"
        let currency = parsed.accountCurrency ?? parsed.currency ?? "TMT"
        let emoji = parsed.accountEmoji ?? Self.defaultEmoji(for: currency)

        let isFirst = accounts.isEmpty
        let account = Account(name: name, currency: currency, emoji: emoji, sortOrder: accounts.count, isDefault: isFirst)
        storage.insertAccount(account)

        if let openingBalance = parsed.amount, openingBalance != 0 {
            let tx = Transaction(
                amount: openingBalance,
                currency: currency,
                desc: "Opening balance",
                category: .other,
                rawInput: raw,
                accountID: account.id
            )
            storage.insertTransaction(tx)
        }

        try? storage.save()
        inputText = ""
        showToast("\(emoji) \(name) created")
    }

    // MARK: - Switch active account

    private func handleSwitchAccount(from parsed: ParsedInput, storage: any StorageRepository) {
        let accounts = storage.fetchAllAccounts()
        guard let name = parsed.sourceAccount,
              let account = resolveAccount(name, in: accounts) else {
            errorMessage = "Couldn't find that wallet -try: \"use cash wallet\""
            return
        }
        storage.setDefaultAccount(account)
        inputText = ""
        showToast("\(account.emoji) \(account.name) is now active")
    }

    // MARK: - Transfer

    private func handleTransfer(from parsed: ParsedInput, raw: String, storage: any StorageRepository) {
        let accounts = storage.fetchAllAccounts()

        guard let sourceAmount = parsed.amount, sourceAmount > 0,
              let sourceCurrency = parsed.currency else {
            errorMessage = "Couldn't parse the transfer -try: transferred 100$ from cash to card"
            return
        }

        let sourceAccount = parsed.sourceAccount.flatMap { resolveAccount($0, in: accounts) }
            ?? storage.fetchDefaultAccount()
        let destAccount = parsed.destinationAccount.flatMap { resolveAccount($0, in: accounts) }
        let destCurrency = destAccount?.currency ?? sourceCurrency

        let destAmount: Double
        if let explicit = parsed.destinationAmount {
            destAmount = explicit
        } else if let rate = parsed.exchangeRate {
            destAmount = sourceAmount * rate
        } else if sourceCurrency == destCurrency {
            destAmount = sourceAmount
        } else {
            errorMessage = "Please add the exchange rate -e.g. \"it was 1\(sourceCurrency)=19.4 \(destCurrency)\""
            return
        }

        let transferID = UUID()
        let destName = destAccount?.name ?? parsed.destinationAccount ?? "account"
        let sourceName = sourceAccount?.name ?? parsed.sourceAccount ?? "account"

        let sourceTx = Transaction(
            amount: -sourceAmount,
            currency: sourceCurrency,
            desc: "To \(destName)",
            category: .transfer,
            rawInput: raw,
            accountID: sourceAccount?.id,
            transferID: transferID,
            counterpartAccountID: destAccount?.id
        )
        let destTx = Transaction(
            amount: destAmount,
            currency: destCurrency,
            desc: "From \(sourceName)",
            category: .transfer,
            rawInput: raw,
            accountID: destAccount?.id,
            transferID: transferID,
            counterpartAccountID: sourceAccount?.id
        )

        storage.insertTransaction(sourceTx)
        storage.insertTransaction(destTx)
        try? storage.save()
        inputText = ""

        if sourceCurrency != destCurrency {
            showToast("\(CurrencyFormatter.format(sourceAmount, showSign: false)) \(sourceCurrency) → \(CurrencyFormatter.format(destAmount, showSign: false)) \(destCurrency)")
        } else {
            showToast("Transfer · \(CurrencyFormatter.format(sourceAmount, showSign: false)) \(sourceCurrency)")
        }
    }

    // MARK: - Helpers

    private func makeTransaction(from parsed: ParsedInput, raw: String, storage: any StorageRepository) -> Transaction? {
        guard parsed.intent == .transaction,
              let amount = parsed.amount,
              let currency = parsed.currency else { return nil }
        let accounts = storage.fetchAllAccounts()
        let account = parsed.sourceAccount.flatMap { resolveAccount($0, in: accounts) }
            ?? storage.fetchDefaultAccount()
        return Transaction(
            amount: amount,
            currency: currency,
            desc: parsed.description ?? (amount >= 0 ? "income" : "expense"),
            category: parsed.category ?? .other,
            rawInput: raw,
            accountID: account?.id
        )
    }

    private func resolveAccount(_ name: String, in accounts: [Account]) -> Account? {
        let lower = name.lowercased()
        if let exact = accounts.first(where: { $0.name.lowercased() == lower }) { return exact }
        if let sub = accounts.first(where: {
            $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased())
        }) { return sub }
        let currencyKeywords: [String: String] = [
            "dollar": "USD", "usd": "USD",
            "euro": "EUR", "eur": "EUR",
            "manat": "TMT", "tmt": "TMT",
            "ruble": "RUB", "rub": "RUB",
            "pound": "GBP", "gbp": "GBP"
        ]
        if let currency = currencyKeywords[lower] {
            return accounts.first { $0.currency == currency }
        }
        return nil
    }

    private static func defaultEmoji(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "💵"
        case "EUR": return "💶"
        case "GBP": return "💷"
        default:    return "💳"
        }
    }

    private func buildContext(storage: any StorageRepository) -> ParserContext {
        let accounts = storage.fetchAllAccounts()
        return ParserContext(accounts: accounts.map {
            ParserContext.AccountInfo(name: $0.name, currency: $0.currency, isDefault: $0.isDefault)
        })
    }

    private func showToast(_ text: String, isError: Bool = false) {
        toast = ToastMessage(text: text, isError: isError)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast?.text == text { toast = nil }
        }
    }
}
