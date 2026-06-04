# Slate - AI Finance Tracker

Natural-language expense and income tracker for iOS. Type or speak what happened — Slate understands and logs it instantly.

```
-50 tmt taxi
salary came in 3000
i received 200$ from my mother
show what I spent on food this month
```

Offline-first. If there's no connection, inputs queue locally and flush automatically when connectivity returns. The transaction's date is always when you entered it, never when it was parsed.

## Features

- Natural language input - English, Russian, Turkmen
- Voice input via SFSpeechRecognizer (English on-device, Russian server-side)
- Query your history: "show food expenses this month" opens a filtered results sheet
- Offline queue: entries are never lost, parsed automatically when back online
- iCloud sync via SwiftData + CloudKit
- Three AI backends: Groq (default, fastest), OpenAI, Gemini
- Swipe to delete transactions
- Date-grouped feed with monthly net balance header

## Requirements

- Xcode 16+
- iOS 17+
- A Groq, OpenAI, or Gemini API key

## Setup

1. Clone the repo
2. Create `slate/Secrets.swift` (already gitignored) with your keys:

```swift
enum Secrets {
    static let groqKey   = "gsk_..."   // default parser
    static let openAIKey = "sk-..."    // optional fallback
    static let geminiKey = "AI..."     // optional fallback
}
```

3. Open `slate.xcodeproj` in Xcode and run on simulator or device.

To switch the active parser, edit `ParserFactory.swift` and return the implementation you want.

## Architecture

```
slate/
  AI/Parsers/     - GroqInputParser (default), CloudInputParser, GeminiInputParser
  Logic/          - CurrencyFormatter, QueryFilter, Theme (Color.brand)
  Models/         - Transaction, PendingInput, TransactionCategory
  Network/        - NetworkMonitor (NWPathMonitor wrapper)
  Storage/        - StorageRepository protocol + SwiftDataStorageRepository
  ViewModels/     - InputViewModel (@Observable)
  Views/          - FeedView, InputBarView, ResultsSheet, ToastView, ...
  Voice/          - SpeechRecognizer + SpeechRecognizerProtocol
```

Key decisions:
- **Parser behind a protocol** - swap Groq for Foundation Models (iOS 26) by changing one line in `ParserFactory`
- **Storage behind a protocol** - `InputViewModel` and `QueueProcessor` never import SwiftData directly
- **Transaction.date = entry time** - offline entries appear at the time the user spoke them, not parse time
- **`@Observable` + Swift 6** - no `ObservableObject`, strict concurrency throughout

## Building

```bash
# Build for iOS simulator
xcodebuild -project slate.xcodeproj -scheme slate -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests
xcodebuild test -project slate.xcodeproj -scheme slateTests -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Roadmap

- [ ] Accounts (Cash, Card, Savings) with per-account balances
- [ ] Transfers between accounts via natural language
- [ ] Custom categories with colors and SF Symbols
- [ ] Charts - spending by category, income vs expenses, balance over time
- [ ] watchOS target
- [ ] macOS target
- [ ] Foundation Models parser (iOS 26, on-device, no network)
