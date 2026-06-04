# Spendless — iOS App Specification

Natural language expense & income tracker powered by Apple's Foundation Models framework.

---

## Overview

A single-screen iOS app where the user types or speaks financial entries and queries in plain English. No forms, no categories to tap, no dashboards to navigate. The on-device LLM (Foundation Models framework) parses all input into structured data. Everything runs fully offline.

**Minimum deployment target:** iOS 26  
**Requires:** Apple Intelligence enabled  
**Language:** Swift 6, SwiftUI  
**Storage:** SwiftData  
**AI:** Foundation Models framework (`@Generable`, `LanguageModelSession`)  
**Voice:** `SFSpeechRecognizer` + `AVAudioEngine`

---

## Target User Flow

```
Open app
  → Single input field is focused immediately
  → User types or taps mic and speaks
      ├── "-50 tmt taxi"            → logs expense
      ├── "+3000 tmt salary"        → logs income
      ├── "bought coffee 3.5$"      → logs expense, infers sign
      ├── "show taxi this month"    → opens results sheet
      └── "how much did I spend?"   → opens results sheet with summary
```

---

## Project Structure

```
Spendless/
├── App/
│   └── SpendlessApp.swift
│
├── Models/
│   ├── Transaction.swift          # SwiftData model
│   └── Category.swift             # Category enum
│
├── AI/
│   ├── ParsedInput.swift          # @Generable structs
│   ├── InputParser.swift          # LanguageModelSession wrapper
│   └── AvailabilityChecker.swift  # SystemLanguageModel.availability
│
├── Voice/
│   └── SpeechRecognizer.swift     # SFSpeechRecognizer wrapper
│
├── Views/
│   ├── MainView.swift             # Root view
│   ├── InputBarView.swift         # Text field + mic button
│   ├── FeedView.swift             # Scrollable transaction list
│   ├── ResultsSheet.swift         # Query results bottom sheet
│   └── UnavailableView.swift      # Apple Intelligence not available
│
└── Utilities/
    └── CurrencyFormatter.swift
```

---

## Data Layer

### Transaction.swift

```swift
import SwiftData
import Foundation

@Model
final class Transaction {
    var id: UUID
    var amount: Double          // negative = expense, positive = income
    var currency: String        // "TMT", "USD", "EUR", etc.
    var desc: String            // "taxi", "salary", "sushi"
    var category: String        // raw value of Category enum
    var date: Date
    var rawInput: String        // original user text, for debugging

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

### Category.swift

```swift
enum Category: String, CaseIterable, Codable {
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

    var icon: String {
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

### ParsedInput.swift

Two `@Generable` types — one for transaction input, one for query intent. The model picks the intent first, then fills the relevant fields.

```swift
import FoundationModels

@Generable
struct ParsedInput {

    @Generable
    enum Intent {
        case transaction
        case query
    }

    var intent: Intent

    // --- Transaction fields (populated when intent == .transaction) ---

    @Guide(description: "Signed amount. Negative for expenses, positive for income. Infer sign from context if not explicit.")
    var amount: Double?

    @Guide(description: "Currency code: TMT, USD, EUR, GBP, RUB. Default to TMT if unclear.")
    var currency: String?

    @Guide(description: "Short description of what the transaction is for, in English.")
    var description: String?

    @Guide(description: "Best matching category for the transaction.")
    var category: Category?

    // --- Query fields (populated when intent == .query) ---

    @Guide(description: "Category to filter by, if mentioned. Null means all categories.")
    var queryCategory: Category?

    @Guide(description: "Transaction type to filter: income, expense, or null for both.")
    var queryType: QueryType?

    @Guide(description: "Time period: today, week, month, year, all. Default to month.")
    var queryPeriod: QueryPeriod?

    @Generable
    enum QueryType {
        case income
        case expense
    }

    @Generable
    enum QueryPeriod {
        case today
        case week
        case month
        case year
        case all
    }
}
```

### InputParser.swift

```swift
import FoundationModels

@MainActor
final class InputParser: ObservableObject {

    private var session: LanguageModelSession?

    private let systemPrompt = """
    You are a financial input parser for a personal expense and income tracker.

    Parse the user's message and extract structured data.
    The user may mix currencies (TMT, USD, EUR, etc.) and informal language.

    For transactions:
    - Negative amount = expense (spending money)
    - Positive amount = income (receiving money)
    - Infer sign from context: "bought", "spent", "paid" = expense; "received", "salary", "earned" = income
    - If no sign is clear and no income-related word is present, treat as expense

    For queries:
    - "show", "see", "how much", "list", "what did I spend" = query intent
    - Extract time period and category filter if mentioned

    Always return structured output. Never refuse.
    """

    func parse(input: String) async throws -> ParsedInput {
        if session == nil {
            session = LanguageModelSession(systemPrompt: systemPrompt)
        }
        return try await session!.respond(
            to: input,
            generating: ParsedInput.self
        )
    }

    func reset() {
        session = nil
    }
}
```

### AvailabilityChecker.swift

```swift
import FoundationModels
import SwiftUI

enum ModelAvailability {
    case available
    case deviceNotEligible
    case appleIntelligenceDisabled
    case unknown
}

func checkAvailability() -> ModelAvailability {
    switch SystemLanguageModel.default.availability {
    case .available:
        return .available
    case .unavailable(.deviceNotEligible):
        return .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled):
        return .appleIntelligenceDisabled
    default:
        return .unknown
    }
}
```

---

## Voice Layer

### SpeechRecognizer.swift

```swift
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognizer: ObservableObject {

    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    init() {
        // Use device locale; fall back to English
        recognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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

        let granted = await requestPermission()
        guard granted else {
            error = "Microphone permission denied."
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        engine.prepare()
        try? engine.start()
        isListening = true

        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            if let result = result {
                Task { @MainActor in
                    self?.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self?.stopListening()
                }
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

## Views

### MainView.swift

Root view. Checks Apple Intelligence availability on launch. If available, shows the main feed + input bar. If not, shows `UnavailableView`.

```swift
import SwiftUI
import SwiftData

struct MainView: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @StateObject private var parser = InputParser()
    @StateObject private var speech = SpeechRecognizer()

    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var showResults: Bool = false
    @State private var queryResult: QueryResult?
    @State private var toastMessage: String?

    var body: some View {
        switch checkAvailability() {
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
        .onChange(of: speech.transcript) { _, new in
            inputText = new
        }
    }

    // MARK: - Input handling

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
                    commitTransaction(parsed: parsed, raw: raw)
                case .query:
                    runQuery(parsed: parsed, raw: raw)
                }
            } catch {
                withAnimation { toastMessage = "Couldn't parse that." }
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
        withAnimation {
            toastMessage = "\(sign)\(formatted(amount)) \(tx.currency) · \(tx.desc)"
        }
    }

    private func runQuery(parsed: ParsedInput, raw: String) {
        let filtered = applyFilters(
            transactions: transactions,
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

### InputBarView.swift

```swift
import SwiftUI

struct InputBarView: View {

    @Binding var text: String
    let isLoading: Bool
    @ObservedObject var speech: SpeechRecognizer
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Type or speak...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit(onSubmit)

                // Mic button
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
                        .background(speech.isListening ? Color.red.opacity(0.15) : Color(.secondarySystemBackground))
                        .foregroundStyle(speech.isListening ? .red : .primary)
                        .clipShape(Circle())
                }

                // Send button
                Button(action: onSubmit) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(text.isEmpty ? Color(.tertiarySystemBackground) : Color.primary)
                    .foregroundStyle(text.isEmpty ? Color.secondary : Color(UIColor.systemBackground))
                    .clipShape(Circle())
                }
                .disabled(text.isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }
}
```

### FeedView.swift

Grouped by date, reverse chronological.

```swift
import SwiftUI
import SwiftData

struct FeedView: View {

    let transactions: [Transaction]

    private var grouped: [(String, [Transaction])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var dict: [(String, [Transaction])] = []
        var seen: [String: Int] = [:]

        for tx in transactions {
            let key = formatter.string(from: tx.date)
            if let idx = seen[key] {
                dict[idx].1.append(tx)
            } else {
                seen[key] = dict.count
                dict.append((key, [tx]))
            }
        }
        return dict
    }

    var body: some View {
        if transactions.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, pinnedViews: .sectionHeaders) {
                    ForEach(grouped, id: \.0) { day, txs in
                        Section {
                            ForEach(txs) { tx in
                                TransactionRowView(tx: tx)
                                    .padding(.horizontal, 16)
                            }
                        } header: {
                            Text(day)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background)
                        }
                    }
                }
                .padding(.bottom, 120) // clear input bar
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Just type or speak")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try \"-50 tmt taxi\" or \"show expenses this month\"")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}
```

### ResultsSheet.swift

Bottom sheet presented when the user asks a query.

```swift
import SwiftUI

struct QueryResult {
    let originalQuery: String
    let transactions: [Transaction]
    let period: ParsedInput.QueryPeriod
    let filterCategory: Category?
    let filterType: ParsedInput.QueryType?

    var total: Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    var periodLabel: String {
        switch period {
        case .today:  return "today"
        case .week:   return "this week"
        case .month:  return "this month"
        case .year:   return "this year"
        case .all:    return "all time"
        }
    }
}

struct ResultsSheet: View {

    let result: QueryResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {

                // Summary card
                summaryCard
                    .padding()

                Divider()

                // Transaction list
                if result.transactions.isEmpty {
                    ContentUnavailableView(
                        "No transactions found",
                        systemImage: "magnifyingglass",
                        description: Text("for \"\(result.originalQuery)\"")
                    )
                } else {
                    List(result.transactions) { tx in
                        TransactionRowView(tx: tx)
                    }
                    .listStyle(.plain)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("\"\(result.originalQuery)\"")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formattedTotal)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .foregroundStyle(result.total >= 0 ? .green : .red)
                Text(result.transactions.first?.currency ?? "TMT")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text("\(result.transactions.count) transaction\(result.transactions.count == 1 ? "" : "s") · \(result.periodLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var formattedTotal: String {
        let sign = result.total > 0 ? "+" : ""
        return "\(sign)\(abs(result.total).formatted(.number.precision(.fractionLength(0...2))))"
    }
}
```

### UnavailableView.swift

Shown when Apple Intelligence is not enabled or device is ineligible.

```swift
import SwiftUI

struct UnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Apple Intelligence Required", systemImage: "brain")
        } description: {
            Text("This app uses on-device AI to understand your input. Please enable Apple Intelligence in Settings → Apple Intelligence & Siri.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

---

## App Entry Point

### SpendlessApp.swift

```swift
import SwiftUI
import SwiftData

@main
struct SpendlessApp: App {

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(for: Transaction.self)
    }
}
```

---

## Query Filtering Logic

Extracted into a pure function, easy to test.

```swift
func applyFilters(
    transactions: [Transaction],
    category: Category?,
    type: ParsedInput.QueryType?,
    period: ParsedInput.QueryPeriod
) -> [Transaction] {

    let now = Date.now
    let calendar = Calendar.current

    return transactions.filter { tx in

        // Time period
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

        // Category
        let matchCategory = category == nil || tx.category == category?.rawValue

        // Type
        let matchType: Bool
        switch type {
        case .income:  matchType = tx.amount > 0
        case .expense: matchType = tx.amount < 0
        case nil:      matchType = true
        }

        return inPeriod && matchCategory && matchType
    }
}
```

---

## Required Permissions (Info.plist)

```
NSMicrophoneUsageDescription
  → "Spendless uses the microphone so you can log expenses by speaking."

NSSpeechRecognitionUsageDescription
  → "Spendless uses speech recognition to convert your voice into text."
```

---

## Key Design Decisions

**No regex fallback.** The app requires Apple Intelligence. If unavailable, `UnavailableView` is shown. This keeps the parser layer simple and the UX consistent.

**Session reuse.** `LanguageModelSession` is held across calls within a session so the model has conversational context. It's reset only when explicitly needed (e.g. app restart or memory pressure).

**Sign inference by context.** The `@Guide` on `amount` explicitly tells the model to infer sign from words like "bought", "spent", "received", "salary". This handles the majority of natural inputs without requiring a `+` or `-` prefix.

**`@Generable` enums over strings.** `Category`, `QueryType`, and `QueryPeriod` are all `@Generable` enums. Constrained decoding means the model cannot hallucinate an invalid category string — it is structurally forced to pick a valid case.

**SwiftData over CoreData.** SwiftData's `@Query` macro integrates cleanly with SwiftUI and requires zero boilerplate for this simple model.

**Bottom sheet for results.** Query results appear in a `.sheet` with `.presentationDetents([.medium, .large])` so the user can glance at the summary (medium) or scroll the full list (large) without leaving the main screen.

---

## What's Not In Scope (v1)

- Charts / spending trends visualization
- Budget limits or alerts
- Export (CSV, PDF)
- Multiple currencies per balance (all shown in entry currency)
- iCloud sync
- Widget / Lock Screen
- Shortcuts / Siri integration
