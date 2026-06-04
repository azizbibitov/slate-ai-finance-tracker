# Slate - AI Finance Tracker

A natural-language expense and income tracker for iOS. Type or speak entries like `-50 tmt taxi` or `salary came in 3000` and Slate parses them automatically via AI.

## Features

- Natural language input in English, Russian, and Turkmen
- Voice input via SFSpeechRecognizer
- Offline-first: entries queue locally and flush when connectivity returns
- iCloud sync via SwiftData + CloudKit
- Multiple AI backends: OpenAI, Gemini, Groq

## Requirements

- Xcode 15+
- iOS 16+
- An OpenAI, Gemini, or Groq API key

## Setup

1. Clone the repo
2. Add a `Secrets.swift` file (gitignored) with your API key:

```swift
enum Secrets {
    static let openAIKey = "sk-..."
}
```

3. Open `slate.xcodeproj` in Xcode and run on a simulator or device.

## Architecture

```
slate/
  AI/           - Parser protocol, OpenAI/Gemini/Groq implementations, queue processor
  Models/       - SwiftData models: Transaction, PendingInput, Category
  Network/      - NWPathMonitor wrapper
  ViewModels/   - Input handling and state
  Views/        - SwiftUI views
  Voice/        - SFSpeechRecognizer wrapper
```

Transactions store a signed `amount` (negative = expense, positive = income). Offline inputs are held in `PendingInput` with their original entry date, so they appear at the correct time in the feed after parsing.

## Building

```bash
# Build for iOS simulator
xcodebuild -project slate.xcodeproj -scheme slate -destination 'platform=iOS Simulator,name=iPhone 15' build

# Run tests
xcodebuild test -project slate.xcodeproj -scheme slateTests -destination 'platform=iOS Simulator,name=iPhone 15'
```
