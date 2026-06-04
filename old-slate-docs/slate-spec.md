# Slate — App Specification

Natural language expense & income tracker. Type or speak. It understands. Fully offline.

**Platforms:** iOS 26 · watchOS 26 · macOS 26  
**Requires:** Apple Intelligence enabled on device  
**Stack:** Swift 6 · SwiftUI · SwiftData · Foundation Models · SFSpeechRecognizer

---

## Concept

One input. No forms. No category pickers. No dashboards to navigate.

You open Slate and say or type what happened — `-50 tmt taxi`, `salary came in 3000`, `show what I spent on food this month` — and Slate handles the rest. The on-device LLM (Apple Foundation Models framework) parses everything into structured data. Nothing leaves the device.

---

## Platform Summary

| | iOS | watchOS | macOS |
|---|---|---|---|
| Log transactions | ✓ text + voice | ✓ voice + quick amounts | ✓ text + voice |
| Query history | ✓ full | ✓ summary only | ✓ full |
| Browse feed | ✓ full | ✓ last 10 entries | ✓ full |
| Foundation Models | ✓ | ✗ (too constrained) | ✓ |
| Speech input | ✓ SFSpeechRecognizer | ✓ WKExtendedRuntimeSession | ✓ SFSpeechRecognizer |
| Data source | SwiftData (iCloud) | Shared via WatchConnectivity | SwiftData (iCloud) |

> **watchOS note:** Foundation Models is not available on watchOS. The watch sends raw input to the paired iPhone for parsing via `WatchConnectivity`, then receives the parsed result back. If the iPhone is unreachable, the watch falls back to a set of quick-entry presets (last 5 categories used).

---

## Project Structure

```
Slate/
│
├── Slate.xcodeproj
│
├── Shared/                          # Pure Swift, no UI, no platform imports
│   ├── Models/
│   │   ├── Transaction.swift        # SwiftData model
│   │   └── Category.swift           # Category enum + icons
│   ├── AI/
│   │   ├── ParsedInput.swift        # @Generable structs (iOS + macOS only)
│   │   └── InputParser.swift        # LanguageModelSession wrapper
│   ├── Logic/
│   │   ├── QueryFilter.swift        # Pure filtering logic (all platforms)
│   │   └── CurrencyFormatter.swift  # Formatting helpers
│   └── Connectivity/
│       └── WatchBridge.swift        # WatchConnectivity shared types
│
├── SlateiOS/                        # iOS target
│   ├── SlateIOSApp.swift
│   ├── Voice/
│   │   └── SpeechRecognizer.swift
│   ├── Views/
│   │   ├── MainView.swift
│   │   ├── InputBarView.swift
│   │   ├── FeedView.swift
│   │   ├── TransactionRowView.swift
│   │   ├── ResultsSheet.swift
│   │   └── UnavailableView.swift
│   └── Connectivity/
│       └── PhoneSessionManager.swift  # Receives watch input, parses, replies
│
├── SlateWatch/                      # watchOS target
│   ├── SlateWatchApp.swift
│   ├── Views/
│   │   ├── WatchMainView.swift
│   │   ├── WatchInputView.swift     # Voice + quick presets
│   │   └── WatchFeedView.swift      # Last 10 entries
│   └── Connectivity/
│       └── WatchSessionManager.swift  # Sends input to phone, receives result
│
└── SlateMac/                        # macOS target
    ├── SlateMacApp.swift
    ├── Voice/
    │   └── SpeechRecognizer.swift   # Same logic as iOS, macOS-specific entitlements
    └── Views/
        ├── MacMainView.swift        # NavigationSplitView layout
        ├── MacInputView.swift
        ├── MacFeedView.swift
        ├── MacResultsView.swift
        └── MacUnavailableView.swift
```

---

## Shared Layer (`Shared/`)

Compiled into all three targets. Zero UIKit, AppKit, or WatchKit imports.

### Models/Transaction.swift

```swift
import SwiftData
import Foundation

@Model
final class Transaction {
    var id: UUID
    var amount: Double          // negative = expense, positive = income
    var currency: String        // "TMT", "USD", "EUR", etc.
    var desc: String            // "taxi", "salary", "sushi"
    var category: String        // Category.rawValue
    var date: Date
    var rawInput: String        // original user text

    init(
        amount: Double,
        currency: String,
        desc: String,
        category: String,
        rawInput: String
    ) {
        self.id = UUID()
        self.amount = amount
        self.currency = currency
        self.desc = desc
        self.category = category
        self.date = .now
        self.rawInput = rawInput
    }
}
```

### Models/Category.swift

```swift
public enum Category: String, CaseIterable, Codable, Sendable {
    case food
    case transport
    case salary
    case shopping
    case health
    case utilities
    case entertainment
    case rent
    case transfer
    case other

    public var sfSymbol: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .salary:        return "briefcase.fill"
        case .shopping:      return "bag.fill"
        case .health:        return "heart.fill"
        case .utilities:     return "bolt.fill"
        case .entertainment: return "gamecontroller.fill"
        case .rent:          return "house.fill"
        case .transfer:      return "arrow.left.arrow.right"
        case .other:         return "circle.fill"
        }
    }
}
```

### Logic/QueryFilter.swift

Pure function. No platform code. Tested independently.

```swift
import Foundation

public struct QueryFilter {

    public static func apply(
        to transactions: [Transaction],
        category: Category? = nil,
        type: ParsedInput.QueryType? = nil,
        period: ParsedInput.QueryPeriod = .month
    ) -> [Transaction] {

        let now = Date.now
        let calendar = Calendar.current

        return transactions.filter { tx in

            let inPeriod: Bool
            switch period {
            case .today:
                inPeriod = calendar.isDateInToday(tx.date)
            case .week:
                let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
                inPeriod = tx.date >= weekAgo
            case .month:
                inPeriod = calendar.isDate(tx.date, equalTo: now, toGranularity: .month)
            case .year:
                inPeriod = calendar.isDate(tx.date, equalTo: now, toGranularity: .year)
            case .all:
                inPeriod = true
            }

            let matchCategory = category == nil || tx.category == category?.rawValue

            let matchType: Bool
            switch type {
            case .income:  matchType = tx.amount > 0
            case .expense: matchType = tx.amount < 0
            case nil:      matchType = true
            }

            return inPeriod && matchCategory && matchType
        }
    }
}
```

### Connectivity/WatchBridge.swift

Shared types for WatchConnectivity messages. Used by both watchOS and iOS targets.

```swift
import Foundation

public enum WatchMessage {

    // Watch → Phone
    public struct ParseRequest: Codable {
        public let requestID: UUID
        public let rawInput: String
        public init(rawInput: String) {
            self.requestID = UUID()
            self.rawInput = rawInput
        }
    }

    // Phone → Watch
    public struct ParseResponse: Codable {
        public let requestID: UUID
        public let result: WatchParseResult
    }

    public enum WatchParseResult: Codable {
        case transaction(amount: Double, currency: String, desc: String, category: String)
        case query(summary: String)       // pre-formatted summary string for watch display
        case failure(reason: String)
    }

    public static let requestKey  = "slate.parse.request"
    public static let responseKey = "slate.parse.response"
}
```

---

## AI Layer (iOS + macOS only)

### AI/ParsedInput.swift

```swift
import FoundationModels

@Generable
public struct ParsedInput {

    @Generable
    public enum Intent {
        case transaction
        case query
    }

    public var intent: Intent

    // Transaction fields
    @Guide(description: "Signed amount. Negative = expense, positive = income. Infer from context words like 'bought', 'spent', 'received', 'salary'.")
    public var amount: Double?

    @Guide(description: "Currency code: TMT, USD, EUR, GBP. Default to TMT if unclear.")
    public var currency: String?

    @Guide(description: "Short description in English, e.g. 'taxi', 'salary', 'groceries'.")
    public var description: String?

    @Guide(description: "Best matching category.")
    public var category: Category?

    // Query fields
    @Guide(description: "Category to filter by. Null means all.")
    public var queryCategory: Category?

    @Guide(description: "Filter by transaction type.")
    public var queryType: QueryType?

    @Guide(description: "Time period to filter. Default to month.")
    public var queryPeriod: QueryPeriod?

    @Generable
    public enum QueryType {
        case income
        case expense
    }

    @Generable
    public enum QueryPeriod {
        case today
        case week
        case month
        case year
        case all
    }
}
```

### AI/InputParser.swift

```swift
import FoundationModels

@MainActor
public final class InputParser: ObservableObject {

    private var session: LanguageModelSession?

    private let systemPrompt = """
    You are a financial input parser for a personal expense and income tracker called Slate.

    Parse the user's message into structured data.
    The user may use informal language and mix currencies (TMT, USD, EUR, etc.).

    Transaction rules:
    - Negative amount = expense (spending money)
    - Positive amount = income (receiving money)
    - Words like "bought", "spent", "paid", "cost" → expense
    - Words like "received", "salary", "earned", "got paid" → income
    - If sign is ambiguous and no income word is present → treat as expense

    Query rules:
    - "show", "see", "how much", "list", "what did I spend", "display" → query intent
    - Extract time period and category filter if mentioned
    - Default time period is month if not specified

    Always return structured output. Never refuse or ask clarifying questions.
    """

    public func parse(input: String) async throws -> ParsedInput {
        if session == nil {
            session = LanguageModelSession(systemPrompt: systemPrompt)
        }
        return try await session!.respond(
            to: input,
            generating: ParsedInput.self
        )
    }

    public func reset() {
        session = nil
    }
}
```

---

## iOS Target (`SlateiOS/`)

### Voice/SpeechRecognizer.swift

```swift
import Speech
import AVFoundation

@MainActor
public final class SpeechRecognizer: ObservableObject {

    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false
    @Published public var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    public init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func startListening() async {
        guard !isListening else { return }
        guard await requestPermission() else {
            error = "Microphone permission denied."
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        try? engine.start()
        isListening = true

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            if let result {
                Task { @MainActor in self?.transcript = result.bestTranscription.formattedString }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self?.stopListening() }
            }
        }
    }

    public func stopListening() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }
}
```

### Connectivity/PhoneSessionManager.swift

Receives raw text from the watch, parses it, sends result back.

```swift
import WatchConnectivity
import Foundation

@MainActor
final class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = PhoneSessionManager()
    private let parser = InputParser()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {

        guard
            let data = message[WatchMessage.requestKey] as? Data,
            let request = try? JSONDecoder().decode(WatchMessage.ParseRequest.self, from: data)
        else { return }

        Task {
            do {
                let parsed = try await parser.parse(input: request.rawInput)
                let result: WatchMessage.WatchParseResult

                switch parsed.intent {
                case .transaction:
                    result = .transaction(
                        amount: parsed.amount ?? 0,
                        currency: parsed.currency ?? "TMT",
                        desc: parsed.description ?? "expense",
                        category: parsed.category?.rawValue ?? "other"
                    )
                case .query:
                    // For watch: return a pre-formatted summary string
                    result = .query(summary: "Feature not available on Watch")
                }

                let response = WatchMessage.ParseResponse(requestID: request.requestID, result: result)
                let data = try JSONEncoder().encode(response)
                replyHandler([WatchMessage.responseKey: data])

            } catch {
                let response = WatchMessage.ParseResponse(
                    requestID: request.requestID,
                    result: .failure(reason: error.localizedDescription)
                )
                let data = (try? JSONEncoder().encode(response)) ?? Data()
                replyHandler([WatchMessage.responseKey: data])
            }
        }
    }

    // Required delegate stubs
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
```

### Views/MainView.swift

```swift
import SwiftUI
import SwiftData
import FoundationModels

struct MainView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @StateObject private var parser = InputParser()
    @StateObject private var speech = SpeechRecognizer()

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showResults = false
    @State private var queryResult: QueryResult?
    @State private var toastMessage: String?

    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            mainContent
        default:
            UnavailableView()
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                headerView
                FeedView(transactions: transactions)
            }
            InputBarView(
                text: $inputText,
                isLoading: isLoading,
                speech: speech,
                onSubmit: handleSubmit
            )
        }
        .sheet(isPresented: $showResults) {
            if let result = queryResult {
                ResultsSheet(result: result)
            }
        }
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
        .onChange(of: speech.transcript) { _, new in inputText = new }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Slate")
                .font(.largeTitle.weight(.semibold))
            Text(balanceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var balanceSummary: String {
        let net = transactions.reduce(0) { $0 + $1.amount }
        let currency = transactions.first?.currency ?? "TMT"
        let sign = net >= 0 ? "+" : ""
        return "Net \(sign)\(abs(net).formatted(.number.precision(.fractionLength(0...2)))) \(currency)"
    }

    private func handleSubmit() {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isLoading else { return }

        inputText = ""
        speech.stopListening()
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let parsed = try await parser.parse(input: raw)
                switch parsed.intent {
                case .transaction: commitTransaction(parsed: parsed, raw: raw)
                case .query:       runQuery(parsed: parsed, raw: raw)
                }
            } catch {
                withAnimation { toastMessage = "Couldn't parse — try again." }
            }
        }
    }

    private func commitTransaction(parsed: ParsedInput, raw: String) {
        guard let amount = parsed.amount else {
            withAnimation { toastMessage = "No amount found." }
            return
        }
        let tx = Transaction(
            amount: amount,
            currency: parsed.currency ?? "TMT",
            desc: parsed.description ?? (amount < 0 ? "expense" : "income"),
            category: parsed.category?.rawValue ?? Category.other.rawValue,
            rawInput: raw
        )
        modelContext.insert(tx)
        let sign = amount > 0 ? "+" : ""
        withAnimation { toastMessage = "\(sign)\(abs(amount).formatted()) \(tx.currency) · \(tx.desc)" }
    }

    private func runQuery(parsed: ParsedInput, raw: String) {
        let filtered = QueryFilter.apply(
            to: transactions,
            category: parsed.queryCategory,
            type: parsed.queryType,
            period: parsed.queryPeriod ?? .month
        )
        queryResult = QueryResult(
            originalQuery: raw,
            transactions: filtered,
            period: parsed.queryPeriod ?? .month,
            filterCategory: parsed.queryCategory,
            filterType: parsed.queryType
        )
        showResults = true
    }
}
```

### Views/ResultsSheet.swift

```swift
import SwiftUI

struct QueryResult {
    let originalQuery: String
    let transactions: [Transaction]
    let period: ParsedInput.QueryPeriod
    let filterCategory: Category?
    let filterType: ParsedInput.QueryType?

    var total: Double { transactions.reduce(0) { $0 + $1.amount } }

    var periodLabel: String {
        switch period {
        case .today: return "today"
        case .week:  return "this week"
        case .month: return "this month"
        case .year:  return "this year"
        case .all:   return "all time"
        }
    }
}

struct ResultsSheet: View {

    let result: QueryResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                }
                if result.transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions found",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    Section {
                        ForEach(result.transactions) { tx in
                            TransactionRowView(tx: tx)
                        }
                    }
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\"\(result.originalQuery)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formattedTotal)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(result.total >= 0 ? .green : .red)
                Text(result.transactions.first?.currency ?? "TMT")
                    .foregroundStyle(.secondary)
            }
            Text("\(result.transactions.count) transaction(s) · \(result.periodLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var formattedTotal: String {
        let sign = result.total > 0 ? "+" : (result.total < 0 ? "-" : "")
        return "\(sign)\(abs(result.total).formatted(.number.precision(.fractionLength(0...2))))"
    }
}
```

---

## watchOS Target (`SlateWatch/`)

The watch has no Foundation Models access. Input (voice or preset) is sent to the paired iPhone via `WatchConnectivity`. The iPhone parses it and replies. The watch then shows a confirmation and optionally stores the transaction locally via the shared `modelContext`.

### Connectivity/WatchSessionManager.swift

```swift
import WatchConnectivity
import Foundation

@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    @Published var lastResponse: WatchMessage.WatchParseResult?
    @Published var isPending = false
    @Published var error: String?

    private var pendingReplyHandlers: [UUID: (WatchMessage.WatchParseResult) -> Void] = [:]

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendForParsing(_ rawInput: String) async -> WatchMessage.WatchParseResult {
        await withCheckedContinuation { continuation in
            let request = WatchMessage.ParseRequest(rawInput: rawInput)
            guard let data = try? JSONEncoder().encode(request) else {
                continuation.resume(returning: .failure(reason: "Encoding failed"))
                return
            }

            isPending = true
            WCSession.default.sendMessage([WatchMessage.requestKey: data], replyHandler: { reply in
                Task { @MainActor in
                    self.isPending = false
                    guard
                        let responseData = reply[WatchMessage.responseKey] as? Data,
                        let response = try? JSONDecoder().decode(WatchMessage.ParseResponse.self, from: responseData)
                    else {
                        continuation.resume(returning: .failure(reason: "Decode failed"))
                        return
                    }
                    continuation.resume(returning: response.result)
                }
            }, errorHandler: { err in
                Task { @MainActor in
                    self.isPending = false
                    continuation.resume(returning: .failure(reason: err.localizedDescription))
                }
            })
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionReachabilityDidChange(_ session: WCSession) {}
}
```

### Views/WatchMainView.swift

```swift
import SwiftUI
import SwiftData

struct WatchMainView: View {

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @StateObject private var session = WatchSessionManager()
    @State private var showInput = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    netBalanceRow
                }
                Section("Recent") {
                    ForEach(transactions.prefix(10)) { tx in
                        watchTransactionRow(tx)
                    }
                }
            }
            .navigationTitle("Slate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInput = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showInput) {
                WatchInputView(session: session)
            }
        }
    }

    private var netBalanceRow: some View {
        let net = transactions.reduce(0) { $0 + $1.amount }
        let currency = transactions.first?.currency ?? "TMT"
        return HStack {
            Text("Balance")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(net >= 0 ? "+" : "")\(abs(net).formatted()) \(currency)")
                .foregroundStyle(net >= 0 ? .green : .red)
                .fontWeight(.medium)
        }
    }

    private func watchTransactionRow(_ tx: Transaction) -> some View {
        HStack {
            Image(systemName: Category(rawValue: tx.category)?.sfSymbol ?? "circle.fill")
                .foregroundStyle(tx.amount >= 0 ? .green : .red)
                .frame(width: 20)
            Text(tx.desc)
                .lineLimit(1)
            Spacer()
            Text("\(tx.amount >= 0 ? "+" : "")\(abs(tx.amount).formatted())")
                .foregroundStyle(tx.amount >= 0 ? .green : .red)
                .font(.caption)
        }
    }
}
```

### Views/WatchInputView.swift

Voice-first. Falls back to last-used category presets if phone is unreachable.

```swift
import SwiftUI
import SwiftData

struct WatchInputView: View {

    @ObservedObject var session: WatchSessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var resultMessage: String?

    enum Phase { case idle, listening, sending, done, error }

    var body: some View {
        VStack(spacing: 12) {
            switch phase {
            case .idle:
                Button {
                    startDictation()
                } label: {
                    Label("Speak", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)

            case .listening:
                Text(transcript.isEmpty ? "Listening..." : transcript)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                ProgressView()

            case .sending:
                Text("Parsing...")
                ProgressView()

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title)
                Text(resultMessage ?? "Saved")
                    .font(.caption)
                    .multilineTextAlignment(.center)

            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title)
                Text(resultMessage ?? "Error")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Button("Try Again") { phase = .idle }
            }
        }
        .padding()
    }

    private func startDictation() {
        // WKExtendedRuntimeSession + SFSpeechRecognizer for watch dictation
        // Simplified here — in practice use the system dictation API
        phase = .listening
        // After dictation completes:
        // transcript = result
        // sendToPhone(transcript)
    }

    private func sendToPhone(_ input: String) {
        phase = .sending
        Task {
            let result = await session.sendForParsing(input)
            switch result {
            case .transaction(let amount, let currency, let desc, let category):
                let tx = Transaction(
                    amount: amount,
                    currency: currency,
                    desc: desc,
                    category: category,
                    rawInput: input
                )
                modelContext.insert(tx)
                resultMessage = "\(amount >= 0 ? "+" : "")\(abs(amount).formatted()) \(currency) · \(desc)"
                phase = .done
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
            case .query:
                resultMessage = "Queries not supported on Watch"
                phase = .error
            case .failure(let reason):
                resultMessage = reason
                phase = .error
            }
        }
    }
}
```

---

## macOS Target (`SlateMac/`)

macOS uses `NavigationSplitView` — sidebar for history/filters, detail for the input and results. Foundation Models and SFSpeechRecognizer work the same as iOS; no special adaptation needed beyond AppKit entitlements.

### Views/MacMainView.swift

```swift
import SwiftUI
import SwiftData
import FoundationModels

struct MacMainView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @StateObject private var parser = InputParser()
    @StateObject private var speech = SpeechRecognizer()

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var selectedResult: QueryResult?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            mainContent
        default:
            MacUnavailableView()
        }
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar — transaction feed
            MacFeedView(transactions: transactions)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            // Detail — input + results
            if let result = selectedResult {
                MacResultsView(result: result, onDismiss: { selectedResult = nil })
            } else {
                MacInputView(
                    text: $inputText,
                    isLoading: isLoading,
                    speech: speech,
                    onSubmit: handleSubmit
                )
            }
        }
        .navigationTitle("Slate")
        .onChange(of: speech.transcript) { _, new in inputText = new }
    }

    private func handleSubmit() {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isLoading else { return }
        inputText = ""
        speech.stopListening()
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let parsed = try await parser.parse(input: raw)
                switch parsed.intent {
                case .transaction:
                    guard let amount = parsed.amount else { return }
                    let tx = Transaction(
                        amount: amount,
                        currency: parsed.currency ?? "TMT",
                        desc: parsed.description ?? (amount < 0 ? "expense" : "income"),
                        category: parsed.category?.rawValue ?? Category.other.rawValue,
                        rawInput: raw
                    )
                    modelContext.insert(tx)
                case .query:
                    let filtered = QueryFilter.apply(
                        to: transactions,
                        category: parsed.queryCategory,
                        type: parsed.queryType,
                        period: parsed.queryPeriod ?? .month
                    )
                    selectedResult = QueryResult(
                        originalQuery: raw,
                        transactions: filtered,
                        period: parsed.queryPeriod ?? .month,
                        filterCategory: parsed.queryCategory,
                        filterType: parsed.queryType
                    )
                }
            } catch { }
        }
    }
}
```

---

## App Entry Points

### SlateIOSApp.swift

```swift
import SwiftUI
import SwiftData

@main
struct SlateIOSApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(for: Transaction.self)
    }

    init() {
        // Start phone session manager so watch messages are received
        _ = PhoneSessionManager.shared
    }
}
```

### SlateWatchApp.swift

```swift
import SwiftUI
import SwiftData

@main
struct SlateWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchMainView()
        }
        .modelContainer(for: Transaction.self)
    }
}
```

### SlateMacApp.swift

```swift
import SwiftUI
import SwiftData

@main
struct SlateMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacMainView()
        }
        .modelContainer(for: Transaction.self)
        .defaultSize(width: 900, height: 600)

        Settings {
            MacSettingsView()
        }
    }
}
```

---

## Data Sync

All three platforms use SwiftData with iCloud (`NSPersistentCloudKitContainer` under the hood). Transactions logged on watch (received from phone and inserted locally) sync to iCloud and appear on iOS and macOS automatically.

```swift
// modelContainer configuration (same across all targets)
.modelContainer(
    for: Transaction.self,
    inMemory: false,
    isAutosaveEnabled: true,
    isUndoEnabled: false
)
```

For iCloud sync, add `iCloud` capability and set `NSPersistentStoreRemoteChangeNotificationPostOptionKey` in the container configuration.

---

## Required Entitlements & Permissions

### iOS

```
NSMicrophoneUsageDescription
  → "Slate uses the microphone so you can log transactions by speaking."

NSSpeechRecognitionUsageDescription
  → "Slate uses speech recognition to convert your voice into text."

com.apple.developer.icloud-services: CloudKit
com.apple.developer.icloud-container-identifiers: iCloud.com.yourname.slate
```

### watchOS

```
com.apple.developer.icloud-services: CloudKit
com.apple.developer.icloud-container-identifiers: iCloud.com.yourname.slate
```

### macOS

```
NSMicrophoneUsageDescription
  → "Slate uses the microphone so you can log transactions by speaking."

NSSpeechRecognitionUsageDescription
  → "Slate uses speech recognition to convert your voice into text."

com.apple.security.device.audio-input: true
com.apple.developer.icloud-services: CloudKit
com.apple.developer.icloud-container-identifiers: iCloud.com.yourname.slate
```

---

## Key Design Decisions

**Shared logic, platform-specific UI.** `Shared/` contains everything that doesn't touch UI frameworks: models, parsing types, query filtering, connectivity message types. Each platform target owns its UI entirely. No `#if os()` hacks in business logic.

**watchOS delegates parsing to iOS.** Foundation Models is not available on watchOS. Rather than shipping a regex fallback that undermines the product, the watch sends raw input to the paired iPhone synchronously via `WatchConnectivity.sendMessage(_:replyHandler:)`. Latency is ~100–300ms over Bluetooth, acceptable for a log action.

**Session reuse across inputs.** `LanguageModelSession` is kept alive across multiple inputs so the model has conversational context within a session. This lets the user say `"actually make that 60 not 50"` and have it understood.

**iCloud sync via SwiftData.** All three targets share the same CloudKit container. A transaction logged on the watch (after phone parsing) appears on Mac and iPhone within seconds. No custom sync code.

**macOS uses NavigationSplitView.** The sidebar shows the transaction feed. The detail pane shows the input field at rest and switches to results when a query is run, avoiding the sheet pattern that doesn't feel native on macOS.

---

## Out of Scope (v1)

- Charts / spending trends
- Budget limits or alerts
- Export (CSV, PDF)
- Multi-account / wallet support
- Shortcuts / Siri integration
- Lock Screen / complications
- Widgets (iOS / macOS)
- Android
