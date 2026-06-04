# Slate — App Specification

Natural language expense & income tracker. Type or speak. It understands. Offline-first.

**Platforms:** iOS · watchOS · macOS  
**Minimum iOS:** iOS 16 (runs on iPhone 11)  
**Stack:** Swift 6 · SwiftUI · SwiftData · SFSpeechRecognizer · WatchConnectivity  
**Parsing (now):** Cloud API (OpenAI / Gemini / Anthropic) behind a repository protocol  
**Parsing (later):** Apple Foundation Models framework (iOS 26, A17 Pro+)  
**Offline strategy:** Queue raw input in SwiftData → flush when connectivity returns  
**Sync:** iCloud via SwiftData (CloudKit)

---

## Concept

One input. No forms. No category pickers.

You open Slate and type or speak what happened:
- `-50 tmt taxi`
- `salary came in 3000`
- `bought coffee 3.5$`
- `show what I spent on food this month`

If online → parsed immediately via Cloud API → saved.  
If offline → raw input queued in SwiftData → parsed automatically when connectivity returns.  
The transaction's date is always when the user entered it — not when it was parsed.

---

## Language Support

| Language | Typed input | Voice (iOS) | Voice (watchOS) | Cloud parsing | Foundation Models (future) |
|---|---|---|---|---|---|
| English | ✅ | ✅ on-device | ✅ | ✅ | ✅ |
| Russian | ✅ | ✅ server-side | ✅ | ✅ | ❌ not supported |
| Turkmen | ✅ | ❌ not supported | ❌ not supported | ✅ | ❌ not supported |

**Voice language note:** `SFSpeechRecognizer` does not support Turkmen. Users who want to speak in Turkmen should type instead. The app shows a friendly message when voice is attempted in an unsupported language. Russian voice works via Apple's server-side recognition (requires internet).

**Onboarding note:** Users are prompted on first launch to download the English (and Russian if relevant) dictation language pack for offline voice:  
`Settings → General → Keyboard → Dictation → Dictation Language`

---

## Platform Summary

| | iOS | watchOS | macOS |
|---|---|---|---|
| Log transactions | ✅ text + voice | ✅ voice + quick presets | ✅ text + voice |
| Query history | ✅ full | ✅ summary only | ✅ full |
| Browse feed | ✅ full | ✅ last 10 entries | ✅ full |
| Offline queue | ✅ | ✅ queues on watch, iPhone flushes | ✅ |
| Cloud parsing | ✅ | ✅ via iPhone (WatchConnectivity) | ✅ |
| Foundation Models (future) | ✅ A17 Pro+ | ❌ not available | ✅ M1+ |
| Voice input | ✅ SFSpeechRecognizer | ✅ WKTextInputController | ✅ SFSpeechRecognizer |
| Data sync | SwiftData + iCloud | SwiftData + iCloud | SwiftData + iCloud |

---

## Parsing Architecture — Repository Pattern

The parser is hidden behind `InputParserProtocol`. Today three cloud implementations exist; later a Foundation Models parser slots in without changing anything else.

```swift
protocol InputParserProtocol: AnyObject {
    func parse(input: String) async throws -> ParsedInput
}
```

```
Implemented:
  InputParserProtocol
    ├── GroqInputParser       (default — llama-3.1-8b-instant, fastest)
    ├── CloudInputParser      (OpenAI gpt-4o-mini)
    └── GeminiInputParser     (Gemini 1.5 Flash)

Later (iOS 26, A17 Pro+):
  InputParserProtocol
    ├── FoundationModelsParser  (on-device, no network)
    └── GroqInputParser / CloudInputParser  (fallback for Russian, older devices)
```

`ParserFactory.make()` returns `GroqInputParser()` by default. Swap to any other implementation there with no other changes.

### Storage — Repository Pattern

Storage is also behind a protocol so SwiftData is never referenced outside the storage layer:

```swift
@MainActor
protocol StorageRepository: AnyObject {
    func insertTransaction(_:), insertPending(_:), deletePending(_:)
    func save() throws
    func fetchPending() -> [PendingInput]
    func fetchAllTransactions() -> [Transaction]
}
```

`SwiftDataStorageRepository` is the only implementation. `InputViewModel` and `QueueProcessor` both depend on the protocol, not on SwiftData directly.

---

## Offline-First Queue

Raw inputs are never lost. If the network is unavailable when the user submits, the raw text is stored in SwiftData as a `PendingInput`. A `NWPathMonitor` watches connectivity. When the network returns, the queue flushes automatically in the background.

```
User submits input (typed or spoken → transcribed to text)
  ↓
NWPathMonitor: online?
  ├── YES → CloudInputParser.parse() → ParsedInput → Transaction → save to SwiftData
  │                                                                  toast: "+50 TMT · taxi"
  └── NO  → PendingInput(rawText, entryDate) → save to SwiftData
              toast: "Saved — will process when back online"
                ↓
              NWPathMonitor fires: network returned
                ↓
              QueueProcessor: fetch all PendingInputs
                ↓
              for each: CloudInputParser.parse() → Transaction(date: pendingInput.entryDate)
                ↓
              delete PendingInput
              silent notification or badge update
```

**Key rule:** `Transaction.date` is always set to `PendingInput.entryDate` (when the user spoke/typed), never to the time of parsing. So "I said -50 tmt taxi at 8pm" appears at 8pm in the feed even if it was parsed at midnight.

---

## Error Handling — Input Layer

Every input outcome has a clear, non-blocking response. Input is never silently lost.

| Situation | User sees |
|---|---|
| Transaction parsed OK | Toast: `+3000 TMT · salary` |
| Query parsed OK | Results sheet opens |
| Parse failed / not understood | Inline error below input field: `"Didn't understand — try: -50 tmt taxi"`. Raw text stays in field. |
| Network offline | Toast: `"Saved — will process when back online"` |
| Network returns, queue flushed | Silent — feed updates automatically |
| Queue item fails to parse after retry | Marked as `failed` in SwiftData. User can review and re-submit or delete. |
| Voice language not supported | Mic button shows error state: `"Voice not available for this language — please type"` |
| Microphone permission denied | `"Microphone access needed for voice input"` with Settings deep link |

---

## Project Structure

Current implementation lives entirely in the `slate/` iOS target. watchOS and macOS targets are planned for v2.

```
slate/
├── slate.xcodeproj
└── slate/
    ├── SlateApp.swift
    ├── ContentView.swift
    ├── Secrets.swift                    # gitignored — API keys
    │
    ├── AI/
    │   ├── InputParserProtocol.swift    # protocol + ParserError
    │   ├── ParsedInput.swift            # shared Codable output type
    │   ├── ParserFactory.swift          # returns GroqInputParser by default
    │   ├── QueueProcessor.swift         # flushes PendingInputs when online
    │   └── Parsers/
    │       ├── GroqInputParser.swift    # default — llama-3.1-8b-instant
    │       ├── CloudInputParser.swift   # OpenAI gpt-4o-mini
    │       └── GeminiInputParser.swift  # Gemini 1.5 Flash
    │
    ├── Logic/
    │   ├── CurrencyFormatter.swift      # single formatting utility
    │   ├── QueryFilter.swift            # pure filter + aggregate
    │   └── Theme.swift                  # Color.brand, Color.brandMuted
    │
    ├── Models/
    │   ├── Transaction.swift            # SwiftData model
    │   ├── PendingInput.swift           # SwiftData model — offline queue
    │   └── Category.swift               # TransactionCategory enum + SF Symbols
    │
    ├── Network/
    │   └── NetworkMonitor.swift         # NWPathMonitor + onConnectionRestored callback
    │
    ├── Storage/
    │   ├── StorageRepository.swift      # protocol
    │   └── SwiftDataStorageRepository.swift
    │
    ├── ViewModels/
    │   └── InputViewModel.swift         # @Observable — all input/submit logic
    │
    ├── Views/
    │   ├── FeedView.swift               # date-grouped list with balance header
    │   ├── InputBarView.swift           # mic + text field + send button
    │   ├── TransactionRowView.swift
    │   ├── PendingRowView.swift
    │   ├── ResultsSheet.swift           # query results sheet
    │   └── ToastView.swift
    │
    └── Voice/
        ├── SpeechRecognizerProtocol.swift  # protocol + RecordingState enum
        └── SpeechRecognizer.swift           # SFSpeechRecognizer wrapper
```

---

## Shared Layer

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
    var date: Date              // when user entered it — NOT parse time
    var rawInput: String

    init(
        amount: Double,
        currency: String,
        desc: String,
        category: String,
        rawInput: String,
        date: Date = .now
    ) {
        self.id = UUID()
        self.amount = amount
        self.currency = currency
        self.desc = desc
        self.category = category
        self.date = date
        self.rawInput = rawInput
    }
}
```

### Models/PendingInput.swift

```swift
import SwiftData
import Foundation

@Model
final class PendingInput {
    var id: UUID
    var rawText: String
    var entryDate: Date         // when user submitted — preserved as Transaction.date
    var retryCount: Int
    var status: Status

    enum Status: String, Codable {
        case pending
        case failed             // shown in UI, user can retry or delete
    }

    init(rawText: String) {
        self.id = UUID()
        self.rawText = rawText
        self.entryDate = .now
        self.retryCount = 0
        self.status = .pending
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

---

## AI Layer

### AI/ParsedInput.swift

Shared output type used by all parser implementations. Codable so it can cross the WatchConnectivity bridge.

```swift
import Foundation

public struct ParsedInput: Codable, Sendable {

    public enum Intent: String, Codable {
        case transaction
        case query
    }

    public enum QueryType: String, Codable {
        case income
        case expense
    }

    public enum QueryPeriod: String, Codable {
        case today
        case week
        case month
        case year
        case all
    }

    public var intent: Intent

    // Transaction fields
    public var amount: Double?
    public var currency: String?
    public var description: String?
    public var category: Category?

    // Query fields
    public var queryCategory: Category?
    public var queryType: QueryType?
    public var queryPeriod: QueryPeriod?
}
```

### AI/CloudInputParser.swift

```swift
import Foundation

final class CloudInputParser: InputParserProtocol {

    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String = Secrets.openAIKey) {
        self.apiKey = apiKey
    }

    private let systemPrompt = """
    You are a financial input parser for a personal expense tracker called Slate.
    Parse the user's message and return ONLY a JSON object. No explanation, no markdown.

    JSON schema:
    {
      "intent": "transaction" | "query",
      "amount": number | null,         // signed: negative = expense, positive = income
      "currency": string | null,       // "TMT", "USD", "EUR", "GBP", "RUB"
      "description": string | null,    // short English description
      "category": string | null,       // one of: food, transport, salary, shopping, health, utilities, entertainment, rent, transfer, other
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
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": input]
            ],
            "temperature": 0,
            "max_tokens": 200
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ParserError.apiError
        }

        let json = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = json.choices.first?.message.content else {
            throw ParserError.emptyResponse
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ParserError.decodingFailed
        }

        return try JSONDecoder().decode(ParsedInput.self, from: jsonData)
    }
}

enum ParserError: Error {
    case apiError
    case emptyResponse
    case decodingFailed
    case notUnderstood
}

// Minimal OpenAI response types
private struct OpenAIResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}
```

### AI/QueueProcessor.swift

```swift
import SwiftData
import Network
import Foundation

@MainActor
final class QueueProcessor: ObservableObject {

    private let parser: InputParserProtocol
    private let modelContext: ModelContext
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "slate.network")

    init(parser: InputParserProtocol, modelContext: ModelContext) {
        self.parser = parser
        self.modelContext = modelContext
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                Task { @MainActor in
                    await self?.flushQueue()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func flushQueue() async {
        let descriptor = FetchDescriptor<PendingInput>(
            predicate: #Predicate { $0.status == "pending" },
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
                if item.retryCount >= 3 {
                    item.status = .failed
                }
            }
        }

        try? modelContext.save()
    }

    private func makeTransaction(from parsed: ParsedInput, raw: String, date: Date) -> Transaction? {
        guard parsed.intent == .transaction, let amount = parsed.amount else { return nil }
        return Transaction(
            amount: amount,
            currency: parsed.currency ?? "TMT",
            desc: parsed.description ?? (amount < 0 ? "expense" : "income"),
            category: parsed.category?.rawValue ?? Category.other.rawValue,
            rawInput: raw,
            date: date                   // ← original entry time, not parse time
        )
    }
}
```

---

## Voice Layer (iOS + macOS)

### SpeechRecognizer.swift

```swift
import Speech
import AVFoundation

@MainActor
final class SpeechRecognizer: ObservableObject {

    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var error: SpeechError?

    enum SpeechError {
        case permissionDenied
        case languageNotSupported
        case unavailable
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    // Supported locales for on-device recognition
    // Turkmen (tk-TM) is NOT in this list — not supported by SFSpeechRecognizer
    static let supportedLocales: [Locale] = [
        Locale(identifier: "en-US"),
        Locale(identifier: "ru-RU")
    ]

    init(locale: Locale = Locale(identifier: "en-US")) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() async {
        guard !isListening else { return }

        guard await requestPermission() else {
            error = .permissionDenied
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            error = .languageNotSupported
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        // Use on-device if available, fall back to server-side gracefully
        if recognizer.supportsOnDeviceRecognition {
            request?.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputNode.outputFormat(forBus: 0)
        ) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        try? engine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request!) { [weak self] result, err in
            if let result {
                Task { @MainActor in
                    self?.transcript = result.bestTranscription.formattedString
                }
            }
            if err != nil || result?.isFinal == true {
                Task { @MainActor in self?.stopListening() }
            }
        }
    }

    func stopListening() {
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

---

## Network Layer

### NetworkMonitor.swift (iOS + macOS)

```swift
import Network
import Foundation

@MainActor
final class NetworkMonitor: ObservableObject {

    @Published private(set) var isConnected: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "slate.networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
```

---

## iOS Views

### InputBarView.swift

Handles all input states: typing, listening, loading, offline, error.

```swift
import SwiftUI

struct InputBarView: View {

    @Binding var text: String
    let isLoading: Bool
    let isOffline: Bool
    @ObservedObject var speech: SpeechRecognizer
    let onSubmit: () -> Void

    @State private var showLanguageHint = false

    var body: some View {
        VStack(spacing: 0) {
            // Offline banner
            if isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                    Text("Offline — inputs will be saved and processed later")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
            }

            // Error hint
            if let err = speech.error {
                Text(errorMessage(for: err))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Type or speak...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit(onSubmit)

                // Mic
                Button {
                    Task {
                        if speech.isListening {
                            speech.stopListening()
                        } else {
                            await speech.startListening()
                        }
                    }
                } label: {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 17))
                        .frame(width: 42, height: 42)
                        .background(
                            speech.isListening
                                ? Color.red.opacity(0.15)
                                : Color(.secondarySystemBackground)
                        )
                        .foregroundStyle(speech.isListening ? .red : .primary)
                        .clipShape(Circle())
                }

                // Send
                Button(action: onSubmit) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else if isOffline {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(text.isEmpty ? Color(.tertiarySystemBackground) : Color.primary)
                    .foregroundStyle(
                        text.isEmpty
                            ? Color.secondary
                            : Color(UIColor.systemBackground)
                    )
                    .clipShape(Circle())
                }
                .disabled(text.isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .onChange(of: speech.transcript) { _, new in text = new }
    }

    private func errorMessage(for error: SpeechRecognizer.SpeechError) -> String {
        switch error {
        case .permissionDenied:      return "Microphone access needed — tap to open Settings"
        case .languageNotSupported:  return "Voice not available for this language — please type"
        case .unavailable:           return "Voice input unavailable right now"
        }
    }
}
```

### MainView.swift

```swift
import SwiftUI
import SwiftData

struct MainView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(predicate: #Predicate<PendingInput> { $0.status == "pending" })
    private var pendingInputs: [PendingInput]
    @Query(predicate: #Predicate<PendingInput> { $0.status == "failed" })
    private var failedInputs: [PendingInput]

    @StateObject private var parser = ParserFactory.makeObservable()
    @StateObject private var speech = SpeechRecognizer()
    @StateObject private var network = NetworkMonitor()

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var showResults = false
    @State private var queryResult: QueryResult?
    @State private var toastMessage: String?
    @State private var toastIsError = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                headerView
                if !failedInputs.isEmpty { failedBanner }
                FeedView(
                    transactions: transactions,
                    pendingInputs: pendingInputs
                )
            }

            InputBarView(
                text: $inputText,
                isLoading: isLoading,
                isOffline: !network.isConnected,
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
                ToastView(message: msg, isError: toastIsError)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Slate")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                if !pendingInputs.isEmpty {
                    Label("\(pendingInputs.count)", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text(balanceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var balanceSummary: String {
        let net = transactions.reduce(0.0) { $0 + $1.amount }
        let currency = transactions.first?.currency ?? "TMT"
        let sign = net >= 0 ? "+" : ""
        return "Net \(sign)\(abs(net).formatted(.number.precision(.fractionLength(0...2)))) \(currency)"
    }

    private var failedBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(failedInputs.count) input(s) couldn't be parsed")
                .font(.caption)
            Spacer()
            Button("Review") { /* navigate to failed inputs list */ }
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - Input handling

    private func handleSubmit() {
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isLoading else { return }

        inputText = ""
        speech.stopListening()

        if !network.isConnected {
            // Offline — queue it
            let pending = PendingInput(rawText: raw)
            modelContext.insert(pending)
            try? modelContext.save()
            showToast("Saved — will process when back online")
            return
        }

        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let parsed = try await parser.parse(input: raw)
                switch parsed.intent {
                case .transaction:
                    commitTransaction(parsed: parsed, raw: raw, date: .now)
                case .query:
                    runQuery(parsed: parsed, raw: raw)
                }
            } catch ParserError.decodingFailed, ParserError.emptyResponse {
                showToast("Didn't understand — try: -50 tmt taxi", isError: true)
                inputText = raw  // put text back so user can rephrase
            } catch {
                showToast("Error — try again", isError: true)
            }
        }
    }

    private func commitTransaction(parsed: ParsedInput, raw: String, date: Date) {
        guard let amount = parsed.amount else {
            showToast("No amount found — try: -50 tmt taxi", isError: true)
            inputText = raw
            return
        }
        let tx = Transaction(
            amount: amount,
            currency: parsed.currency ?? "TMT",
            desc: parsed.description ?? (amount < 0 ? "expense" : "income"),
            category: parsed.category?.rawValue ?? Category.other.rawValue,
            rawInput: raw,
            date: date
        )
        modelContext.insert(tx)
        let sign = amount > 0 ? "+" : ""
        showToast("\(sign)\(abs(amount).formatted()) \(tx.currency) · \(tx.desc)")
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

    private func showToast(_ message: String, isError: Bool = false) {
        withAnimation {
            toastMessage = message
            toastIsError = isError
        }
    }
}
```

---

## watchOS Layer

### WatchInputView.swift

Uses `WKTextInputController` (the system watch dictation modal). Sends raw text to iPhone for parsing via `WatchConnectivity`. If iPhone is unreachable, queues locally.

```swift
import SwiftUI
import WatchKit
import SwiftData

struct WatchInputView: View {

    @ObservedObject var session: WatchSessionManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .idle
    @State private var resultMessage: String?

    enum Phase { case idle, sending, done, error, queued }

    // Quick presets — last used categories
    let suggestions = ["-50 tmt taxi", "+3000 tmt salary", "-20 tmt food", "-5 tmt coffee"]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch phase {
                case .idle:
                    Button {
                        presentDictation()
                    } label: {
                        Label("Speak", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    // Quick presets
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) {
                            send(suggestion)
                        }
                        .font(.caption)
                    }

                case .sending:
                    ProgressView("Parsing...")

                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title)
                    Text(resultMessage ?? "Saved")
                        .font(.caption)
                        .multilineTextAlignment(.center)

                case .queued:
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                        .font(.title)
                    Text("Saved — iPhone will process this later")
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
    }

    private func presentDictation() {
        WKExtension.shared().visibleInterfaceController?.presentTextInputController(
            withSuggestions: suggestions,
            allowedInputModes: [.plain]
        ) { results in
            guard let text = results?.first as? String, !text.isEmpty else { return }
            send(text)
        }
    }

    private func send(_ text: String) {
        guard session.isPhoneReachable else {
            // Queue locally — iPhone will flush when connected
            let pending = PendingInput(rawText: text)
            modelContext.insert(pending)
            try? modelContext.save()
            phase = .queued
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
            return
        }

        phase = .sending

        Task {
            let result = await session.sendForParsing(text)
            switch result {
            case .transaction(let amount, let currency, let desc, let category):
                let tx = Transaction(
                    amount: amount,
                    currency: currency,
                    desc: desc,
                    category: category,
                    rawInput: text,
                    date: .now
                )
                modelContext.insert(tx)
                let sign = amount >= 0 ? "+" : ""
                resultMessage = "\(sign)\(abs(amount).formatted()) \(currency) · \(desc)"
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

### WatchSessionManager.swift

```swift
import WatchConnectivity
import Foundation

@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    @Published var isPhoneReachable: Bool = false

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

            WCSession.default.sendMessage(
                [WatchMessage.requestKey: data],
                replyHandler: { reply in
                    Task { @MainActor in
                        guard
                            let responseData = reply[WatchMessage.responseKey] as? Data,
                            let response = try? JSONDecoder().decode(
                                WatchMessage.ParseResponse.self,
                                from: responseData
                            )
                        else {
                            continuation.resume(returning: .failure(reason: "Decode failed"))
                            return
                        }
                        continuation.resume(returning: response.result)
                    }
                },
                errorHandler: { err in
                    Task { @MainActor in
                        continuation.resume(returning: .failure(reason: err.localizedDescription))
                    }
                }
            )
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        isPhoneReachable = session.isReachable
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        isPhoneReachable = session.isReachable
    }
}
```

---

## Connectivity Bridge

### WatchBridge.swift

```swift
import Foundation

public enum WatchMessage {

    public struct ParseRequest: Codable {
        public let requestID: UUID
        public let rawInput: String
        public init(rawInput: String) {
            self.requestID = UUID()
            self.rawInput = rawInput
        }
    }

    public struct ParseResponse: Codable {
        public let requestID: UUID
        public let result: WatchParseResult
    }

    public enum WatchParseResult: Codable {
        case transaction(amount: Double, currency: String, desc: String, category: String)
        case query(summary: String)
        case failure(reason: String)
    }

    public static let requestKey  = "slate.parse.request"
    public static let responseKey = "slate.parse.response"
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

    @StateObject private var queueProcessor: QueueProcessor

    init() {
        let container = try! ModelContainer(for: Transaction.self, PendingInput.self)
        let parser = ParserFactory.make()
        _queueProcessor = StateObject(
            wrappedValue: QueueProcessor(
                parser: parser,
                modelContext: container.mainContext
            )
        )
        _ = PhoneSessionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(for: [Transaction.self, PendingInput.self])
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
        .modelContainer(for: [Transaction.self, PendingInput.self])
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
        .modelContainer(for: [Transaction.self, PendingInput.self])
        .defaultSize(width: 960, height: 620)

        Settings {
            MacSettingsView()
        }
    }
}
```

---

## Onboarding (First Launch)

Shown once on iOS. Prompts the user to download dictation packs for offline voice.

```swift
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.primary)

            Text("Enable Offline Voice")
                .font(.title2.weight(.semibold))

            Text("For voice input without internet, download the dictation language pack:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Settings → General → Keyboard\n→ Dictation → Dictation Language")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Open Settings") {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
            .buttonStyle(.borderedProminent)

            Button("Skip") {
                hasSeenOnboarding = true
            }
            .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
```

---

## Required Permissions

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

**Repository pattern for parsing.** `InputParserProtocol` decouples all app logic from the parsing implementation. Switching from Cloud API to Foundation Models later requires changing one file (`ParserFactory.swift`) and adding one new class (`FoundationModelsParser`). Nothing else changes.

**Offline queue in SwiftData.** `PendingInput` is a first-class model, not an in-memory array. It survives app restarts, device reboots, and background termination. When the app next has connectivity — whether opened immediately or days later — the queue flushes automatically.

**Transaction date = entry date, not parse date.** A transaction logged offline at 8pm appears at 8pm in the feed, even if it was parsed at midnight. This is essential for the mental model of the app feeling like a real-time ledger.

**Watch queues locally, iPhone parses.** When the paired iPhone is unreachable, the watch stores `PendingInput` items in its own SwiftData store. When the iPhone becomes reachable again via WatchConnectivity, it picks them up and parses them. iCloud sync propagates the resulting transactions back to the watch.

**Voice error states are explicit.** Language not supported, permission denied, and unavailable are three distinct states shown inline — no silent failures, no generic "error" messages.

**Turkmen typed input works everywhere.** Cloud APIs (OpenAI, Gemini) handle written Turkmen for short financial inputs. Voice in Turkmen is not supported by `SFSpeechRecognizer` and users are directed to type instead.

---

## Switching to Foundation Models Later

When you have an Apple Intelligence-capable device (iPhone 15 Pro or newer, iOS 26):

1. Add `FoundationModelsParser.swift` implementing `InputParserProtocol` using `@Generable` + `LanguageModelSession`
2. Update `ParserFactory.make()`:

```swift
static func make() -> InputParserProtocol {
    if #available(iOS 26, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
            return FoundationModelsParser()
        default:
            break
        }
    }
    return CloudInputParser()
}
```

3. Keep `CloudInputParser` as fallback for older devices and Russian language support.

That's it. No other changes anywhere in the app.

---

## Out of Scope (v1)

- Budget limits or alerts
- Export (CSV, PDF)
- Shortcuts / Siri integration
- Lock Screen widget / complications
- Android

---

## Roadmap — v2 Features

### Accounts

Users can have multiple named accounts (Cash, Card, Savings, etc.) in different currencies. Every transaction belongs to an account. Transfers move money between two accounts and appear as a single entry in the feed (not two separate transactions).

**Model additions:**

```swift
@Model
final class Account {
    var id: UUID
    var name: String       // "Cash", "Kapitalbank", "Savings"
    var currency: String   // primary currency for this account
    var emoji: String      // "💵", "🏦", "💳"
    var sortOrder: Int
    var isArchived: Bool

    init(name: String, currency: String, emoji: String) { ... }
}
```

`Transaction` gains an optional `accountID: UUID?` — nil means "no account" (backwards compatible with existing data).

**Transfer model:**

A transfer is a special transaction pair: one negative on the source account and one positive on the destination account, linked by a shared `transferID: UUID`. The feed shows them as a single row.

```swift
// Transaction additions
var transferID: UUID?          // non-nil when part of a transfer pair
var destinationAccountID: UUID? // non-nil on the positive leg
```

**Natural language examples:**

- `"transferred 500 tmt from cash to card"` → transfer between accounts
- `"moved 200$ to savings"` → transfer, source = current default account
- `"received 200$ from my mother"` → income, no transfer, category = other

**Parser additions to `ParsedInput`:**

```swift
// Transfer fields (only when intent == .transfer)
var sourceAccount: String?       // matched against known account names
var destinationAccount: String?
```

`Intent` gains a `.transfer` case.

---

### Categories (Enhanced)

Current categories are hardcoded in `TransactionCategory`. In v2, users can create custom categories with a name, SF Symbol, and color. Built-in categories remain but are editable.

**Model:**

```swift
@Model
final class Category {
    var id: UUID
    var name: String
    var sfSymbol: String
    var colorHex: String    // brand/accent color for this category
    var isBuiltIn: Bool
    var sortOrder: Int
}
```

`Transaction.category` changes from `String` (rawValue) to `UUID` (foreign key to `Category`). A migration is needed.

The parser returns a category name string; the app resolves it to a `Category` by fuzzy-matching on name.

---

### Charts

A dedicated Charts tab (iOS, macOS) showing spending trends over time.

**Views:**

- **Spending by category** — pie/donut chart for the selected period (week, month, year)
- **Income vs expenses** — bar chart grouped by week or month
- **Balance over time** — line chart per account or total

**Implementation:** Swift Charts (`import Charts`), iOS 16+.

**Data layer:** `QueryFilter` already handles period filtering. Charts just aggregate the output into `[(label: String, value: Double)]` series.

**Natural language query integration:** "show me a chart of food spending this year" → opens Charts tab filtered to food/year.

---

### Transfer Parser Flow

When the parser returns `intent == .transfer`:

1. `InputViewModel` resolves `sourceAccount` and `destinationAccount` strings to `Account` objects (fuzzy match on name)
2. Creates two `Transaction` objects with a shared `transferID`
3. One is negative on the source account, one is positive on the destination
4. Feed shows them as a single "Transfer" row with → arrow

If account names can't be resolved, fall back to asking the user to clarify (inline prompt below the input bar).
