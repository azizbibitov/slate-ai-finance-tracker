# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Slate is a natural-language expense and income tracker. The user types or speaks entries like `spent 50 tmt taxi` or `+500$ upwork`, and the app parses them via Groq (llama-3.1-8b-instant). It is offline-first: unprocessed inputs queue in SwiftData and flush automatically when connectivity returns.

**Stack:** Swift 6, SwiftUI, SwiftData, SFSpeechRecognizer, NWPathMonitor  
**Platforms:** iOS 17+  
**Sync:** iCloud via SwiftData + CloudKit

## Building and Running

This is an Xcode project. Build and run via Xcode only - never run xcodebuild.

## Architecture

All code lives in `slate/` (iOS only - no watchOS or macOS targets yet):

```
slate/
  AI/
    Parsers/          - GroqInputParser (only active parser)
    InputParserProtocol.swift - protocol + ParserContext + ParserError
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
    FeedView.swift, InputBarView.swift
    AccountsSheet.swift  - contains GlobalSheet + private AccountsContent
    ResultsSheet.swift   - content-only view (no NavigationStack), used by GlobalSheet
    TransactionRowView.swift, TransferRowView.swift
    PendingRowView.swift, ToastView.swift
  Voice/
    SpeechRecognizer.swift + SpeechRecognizerProtocol.swift
```

### Key Data Models

- `Transaction` - persisted result. `amount` is signed (negative = expense, positive = income). `date` is always the entry time, never parse time. Optional `accountID`, `transferID`, `counterpartAccountID`.
- `PendingInput` - raw text queued when offline. `entryDate` is preserved as `Transaction.date` on flush.
- `Account` - wallet with `name`, `currency`, `emoji`, `isDefault`, `isArchived`. One account is the active/default wallet at a time.
- `TransactionCategory` - `food, transport, salary, shopping, health, utilities, entertainment, rent, transfer, other`. Decodes leniently (unknown strings fall back to `.other`).

### Parser / AI Layer

Only `GroqInputParser` is active. `ParserFactory.make()` returns it. `ParsedInput` has these intents:
- `.transaction` - regular income or expense
- `.transfer` - between two accounts
- `.createAccount` - natural language wallet creation
- `.switchAccount` - change the active wallet
- `.query` - history/balance queries
- `.unknown` - non-financial input; app shows an error instead of logging anything

`ParserContext` is built fresh on every `parse(input:context:)` call. It carries the user's current account names, currencies, and which wallet is active. `GroqInputParser.contextSection(_:)` appends this as a wallet list to the system prompt so the model resolves account references against real names.

`TransactionCategory` has a custom `init(from:)` that falls back to `.other` for any unknown string the LLM returns.

`GroqInputParser` also strips `: +500` JSON patterns to `: 500` before decoding (LLMs sometimes emit `+number` which is invalid JSON).

### Wallet / Account Logic

Every transaction attaches to an account via `accountID`. `InputViewModel` resolves the account in this order:
1. If the user named a wallet in their input (`parsed.sourceAccount`) - fuzzy match (exact -> substring -> currency keyword)
2. Otherwise - the default account (`isDefault == true`)
3. Fallback - first account in the list

The first created account becomes default automatically. Active wallet can be switched by voice/text via the `switchAccount` intent.

### UI Structure

`ContentView` shows `FeedView` (today only - flat list, no tabs or period filters). `InputBarView` sits as a `safeAreaInset` at the bottom.

One persistent `GlobalSheet` (in `AccountsSheet.swift`) handles both wallets and query results. It is presented via `isPresented: Binding(get: { vm.activeSheet != nil }, ...)` so the sheet stays open when `vm.activeSheet` switches between `.accounts` and `.results(QueryResult)`. Content swaps inside using `matchedGeometryEffect` + spring animation. `InputBarView` is embedded in `GlobalSheet` so all operations work from within the sheet.

`InputViewModel.activeSheet: ActiveSheet?` drives the sheet:
- `.accounts` - shows wallet list
- `.results(QueryResult)` - shows query results

### Offline-First Rule

Never set `Transaction.date` to the current time during queue flush. Always use `PendingInput.entryDate`.

### Language Support

The parser handles English, Russian, and Turkmen. Voice via `SFSpeechRecognizer` supports English (on-device) and Russian (server-side). Turkmen voice is not supported.

### API Keys

Accessed via `Secrets.groqKey`. Keep keys out of source - `Secrets.swift` is gitignored.

### Xcode Project Files

Never edit `project.pbxproj` directly. When new Swift files are created, the user adds them to the Xcode project manually.
