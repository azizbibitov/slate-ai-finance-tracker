# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Slate is a natural-language expense and income tracker. The user types or speaks entries like `-50 tmt taxi` or `salary came in 3000`, and the app parses them via a Cloud API (OpenAI / Gemini / Anthropic). It is offline-first: unprocessed inputs queue in SwiftData and flush automatically when connectivity returns.

**Stack:** Swift 6, SwiftUI, SwiftData, SFSpeechRecognizer, WatchConnectivity, NWPathMonitor  
**Platforms:** iOS 16+, watchOS, macOS  
**Sync:** iCloud via SwiftData + CloudKit

## Building and Running

This is an Xcode project. Build and run via Xcode or:

```bash
# Build for iOS simulator
xcodebuild -project slate.xcodeproj -scheme slate -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests
xcodebuild test -project slate.xcodeproj -scheme slateTests -destination 'platform=iOS Simulator,name=iPhone 15'

# Run a single test class
xcodebuild test -project slate.xcodeproj -scheme slateTests -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:slateTests/YourTestClass
```

## Architecture

The codebase is structured into a shared layer and per-platform layers. Right now only the iOS scaffold exists (`slate/`); the full target layout per the spec is:

```
Shared/          - Pure Swift (no UIKit/AppKit/WatchKit)
  Models/        - SwiftData models: Transaction, PendingInput, Category
  AI/            - Parser protocol + implementations + QueueProcessor
  Logic/         - QueryFilter, CurrencyFormatter
  Connectivity/  - WatchBridge (shared WatchConnectivity message types)

SlateiOS/        - iOS target
SlateWatch/      - watchOS target (routes parse requests to iPhone via WatchConnectivity)
SlateMac/        - macOS target
```

### Key Data Models

- `Transaction` - the persisted result of a parsed input. `amount` is signed (negative = expense, positive = income). `date` is always the time the user entered the text, never the parse time.
- `PendingInput` - raw text queued when offline. Has `entryDate` (preserved as `Transaction.date` on flush), `retryCount`, and a `Status` of `.pending` or `.failed`.
- `Category` - enum with SF Symbol mappings.

### Parser / AI Layer

The parser sits behind `InputParserProtocol`. `CloudInputParser` implements it today using OpenAI `gpt-4o-mini`. A `ParserFactory` resolves the implementation at runtime (future: Foundation Models on iOS 26 / A17 Pro+).

`QueueProcessor` holds an `NWPathMonitor`. When connectivity is restored it fetches all `.pending` `PendingInput` records, parses them, writes `Transaction` objects with the original `entryDate`, and deletes the pending records.

### Offline-First Rule

Never set `Transaction.date` to the current time during queue flush. Always use `PendingInput.entryDate` so transactions appear at the time the user entered them.

### Watch Architecture

watchOS has no direct network access for parsing. The watch queues inputs as `PendingInput` records in its local SwiftData store and sends them to the iPhone via `WatchConnectivity`. The iPhone's `PhoneSessionManager` handles them, parses, and syncs results back via iCloud.

### Language Support

The parser handles English, Russian, and Turkmen input. Voice via `SFSpeechRecognizer` supports English (on-device) and Russian (server-side). Turkmen voice is not supported - show a friendly message instead of attempting recognition.

### API Keys

API keys (OpenAI etc.) are accessed via `Secrets.openAIKey`. Keep keys out of source - use a `Secrets.swift` that is gitignored or an xcconfig approach.
