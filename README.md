# Slate - AI Finance Tracker

Natural-language expense and income tracker for iOS. Type or speak what happened — Slate understands and logs it instantly.

```
spent 50 tmt on taxi
+500$ upwork
i received 200$ from my mother
transferred 100$ to tmt wallet at rate 19.4
show food expenses this month
I have a cash wallet with 5000 tmt
```

Offline-first. If there's no connection, inputs queue locally and flush automatically when connectivity returns. The transaction's date is always when you entered it, never when it was parsed.

## Features

- Natural language input - English, Russian, Turkmen
- Voice input via SFSpeechRecognizer (English on-device, Russian server-side)
- Multiple wallets with different currencies - one active wallet receives all transactions by default
- Transfers between wallets, including cross-currency with user-stated rate
- Expense and income tabs with Day / Week / Month / Year period filter
- Query history: "show food expenses this month", "show accounts", "expenses for [name] last week"
- Categories auto-detected by AI: food, transport, salary, shopping, health, utilities, entertainment, rent, other
- Offline queue: entries are never lost, parsed automatically when back online
- iCloud sync via SwiftData + CloudKit
- Swipe to delete transactions

## Requirements

- Xcode 16+
- iOS 17+
- A Groq API key (free tier available at console.groq.com)

## Setup

1. Clone the repo
2. Create `slate/Secrets.swift` (already gitignored):

```swift
enum Secrets {
    static let groqKey = "gsk_..."
}
```

3. Open `slate.xcodeproj` in Xcode and run on simulator or device.

## Architecture

```
slate/
  AI/Parsers/     - GroqInputParser (llama-3.1-8b-instant)
  Logic/          - CurrencyFormatter, QueryFilter, Theme
  Models/         - Transaction, PendingInput, Account, TransactionCategory
  Storage/        - StorageRepository protocol + SwiftDataStorageRepository
  ViewModels/     - InputViewModel (@Observable)
  Views/          - FeedView, AccountsSheet, InputBarView, ResultsSheet, ...
  Voice/          - SpeechRecognizer
```

Key decisions:
- **Parser behind a protocol** - swap Groq for Foundation Models (iOS 26) by changing one line in `ParserFactory`
- **Storage behind a protocol** - `InputViewModel` and `QueueProcessor` never import SwiftData directly
- **Transaction.date = entry time** - offline entries appear at the time the user spoke them, not parse time
- **`@Observable` + Swift 6** - no `ObservableObject`, strict concurrency throughout
- **Lenient category decoding** - unknown AI-returned category strings fall back to `.other` instead of crashing

## Roadmap

- [ ] Charts - spending by category, income vs expenses, balance over time
- [ ] watchOS target
- [ ] Foundation Models parser (iOS 26, on-device, no API key needed)
