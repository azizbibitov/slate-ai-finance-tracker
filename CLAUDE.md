# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Slate is a natural-language expense and income tracker. The user types or speaks entries like `spent 50 tmt taxi` or `+500$ upwork`, and the app parses them via Groq (llama-3.1-8b-instant). It is offline-first: unprocessed inputs queue in SwiftData and flush automatically when connectivity returns.

**Stack:** Swift 6, SwiftUI, SwiftData, SFSpeechRecognizer, NWPathMonitor  
**Platforms:** iOS 17+  
**Sync:** iCloud via SwiftData + CloudKit

## Building and Running

This is an Xcode project. Build and run via Xcode or:

```bash
# Build for iOS simulator
xcodebuild -project slate.xcodeproj -scheme slate -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests
xcodebuild test -project slate.xcodeproj -scheme slateTests -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Architecture

All code lives in `slate/` (iOS only - no watchOS or macOS targets yet):

```
slate/
  AI/
    Parsers/          - GroqInputParser (only active parser)
    InputParserProtocol.swift
    ParsedInput.swift - Codable output struct shared by all parsers
    ParserFactory.swift
    QueueProcessor.swift
  Logic/
    CurrencyFormatter.swift
    QueryFilter.swift
    Theme.swift       - Color.brand, Color.brandMuted extensions
  Models/
    Transaction.swift
    PendingInput.swift
    Account.swift
    Category.swift    - TransactionCategory enum
  Storage/
    StorageRepository.swift (protocol)
    SwiftDataStorageRepository.swift
  ViewModels/
    InputViewModel.swift (@Observable, @MainActor)
  Views/
    FeedView.swift, InputBarView.swift, ResultsSheet.swift
    AccountsSheet.swift, TransactionRowView.swift
    TransferRowView.swift, PendingRowView.swift, ToastView.swift
  Voice/
    SpeechRecognizer.swift + SpeechRecognizerProtocol.swift
```

### Key Data Models

- `Transaction` - persisted result. `amount` is signed (negative = expense, positive = income). `date` is always the entry time, never parse time. Optional `accountID`, `transferID`, `counterpartAccountID`.
- `PendingInput` - raw text queued when offline. `entryDate` is preserved as `Transaction.date` on flush.
- `Account` - wallet with `name`, `currency`, `emoji`, `isDefault`, `isArchived`. One account is the active/default wallet at a time.
- `TransactionCategory` - `food, transport, salary, shopping, health, utilities, entertainment, rent, transfer, other`. Decodes leniently (unknown strings fall back to `.other`).

### Parser / AI Layer

Only `GroqInputParser` is active. `ParserFactory.make()` returns it. `ParsedInput` has 4 intents:
- `.transaction` - regular income or expense
- `.transfer` - between two accounts
- `.createAccount` - natural language wallet creation
- `.query` - history/balance queries

`TransactionCategory` has a custom `init(from:)` that falls back to `.other` for any unknown string the LLM returns.

`GroqInputParser` also strips `: +500` JSON patterns to `: 500` before decoding (LLMs sometimes emit `+number` which is invalid JSON).

### Wallet / Account Logic

Every transaction attaches to an account via `accountID`. `InputViewModel` resolves the account in this order:
1. If the user named a wallet in their input (`parsed.sourceAccount`) - fuzzy match (exact → substring → currency keyword)
2. Otherwise - the default account (`isDefault == true`)
3. Fallback - first account in the list

The first created account becomes default automatically. Tapping an account in `AccountsSheet` sets it as the new default.

### Offline-First Rule

Never set `Transaction.date` to the current time during queue flush. Always use `PendingInput.entryDate`.

### UI Structure

`ContentView` owns `selectedTab: FeedTab` (.expense/.income) and `selectedPeriod: FeedPeriod` (.day/.week/.month/.year), passed as bindings to `FeedView`. The tab switcher and period chips live inside the FeedView balance header. `InputBarView` sits as a `safeAreaInset` at the bottom.

### Language Support

The parser handles English, Russian, and Turkmen. Voice via `SFSpeechRecognizer` supports English (on-device) and Russian (server-side). Turkmen voice is not supported.

### API Keys

Accessed via `Secrets.groqKey`. Keep keys out of source - `Secrets.swift` is gitignored.

### Xcode Project Files

Never edit `project.pbxproj` directly. When new Swift files are created, the user adds them to the Xcode project manually.
