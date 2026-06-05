# Slate — MLX-Swift Integration Guide

Adding on-device LLM parsing as a fallback for devices without Apple Intelligence.

---

## Overview

Slate uses a three-tier parser:

```
Tier 1: Foundation Models   iOS 26 + A17 Pro+   on-device, free, no download
Tier 2: MLX-Swift           iOS 18+ + Metal     on-device, free, one-time ~300MB download
Tier 3: Groq (cloud)        any device          online only, queued when offline
```

This document covers adding **Tier 2: MLX-Swift**.

---

## Repositories

There are three repos involved. You only add two as SPM dependencies:

| Repo | Purpose | Add to SPM? |
|---|---|---|
| `ml-explore/mlx-swift` | Core MLX array framework | ❌ pulled in automatically |
| `ml-explore/mlx-swift-lm` | LLM inference library (`MLXLLM`, `MLXLMCommon`) | ✅ yes |
| `huggingface/swift-huggingface` | Download client with progress + resume | ✅ yes |
| `huggingface/swift-transformers` | Tokenizer support | ✅ yes |

> **Note:** `MLXLLM` and `MLXLMCommon` moved from `mlx-swift-examples` to `mlx-swift-lm` in version 3.x. Use `mlx-swift-lm` — not `mlx-swift-examples`.

---

## SPM Dependencies

In Xcode → Project → Package Dependencies, add:

```
https://github.com/ml-explore/mlx-swift-lm
https://github.com/huggingface/swift-huggingface
https://github.com/huggingface/swift-transformers
```

Or in `Package.swift` (if using SPM directly):

```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift-lm",
             .upToNextMajor(from: "3.31.3")),
    .package(url: "https://github.com/huggingface/swift-huggingface",
             from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers",
             from: "1.3.0"),
],
targets: [
    .target(
        name: "SlateiOS",
        dependencies: [
            .product(name: "MLXLLM",        package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon",   package: "mlx-swift-lm"),
            .product(name: "MLXHuggingFace",package: "mlx-swift-lm"),
            .product(name: "HuggingFace",   package: "swift-huggingface"),
            .product(name: "Tokenizers",    package: "swift-transformers"),
        ]
    )
]
```

Add to **iOS and macOS targets only** — not watchOS.

---

## Model Choice

**`mlx-community/Qwen2.5-0.5B-Instruct-4bit`**

- Size: ~300MB download
- RAM: ~350MB at runtime
- Works on: iPhone 11+ (4GB RAM), any Metal-capable device
- Languages: English, Russian, Chinese, and more — handles mixed input well
- Speed: slow on A13 (~3 tok/sec), faster on newer chips
- License: Apache 2.0, free, no API key needed

For iPhone 11 specifically (4GB RAM), this is the largest model that fits comfortably alongside the rest of the app. Do not use 1B or larger models on iPhone 11 — OOM risk.

---

## Download Behavior

### Does it provide download progress? ✅ Yes

`loadContainer` accepts a `progressHandler` closure that fires per-file with a `Progress` object:

```swift
try await LLMModelFactory.shared.loadContainer(
    from: HubClient.default,
    using: TokenizersLoader(),
    configuration: config,
    progressHandler: { progress in
        // progress.fractionCompleted  → 0.0 to 1.0
        // progress.completedUnitCount → files completed
        // progress.totalUnitCount     → total files
        print("\(Int(progress.fractionCompleted * 100))%")
    }
)
```

Progress is per-file (the model has several `.safetensors` shards + config files). It is not per-byte within a single file — so it jumps in steps, not smoothly. Design your UI accordingly (step-based progress bar, not smooth fill).

### Does it resume interrupted downloads? ⚠️ Partially

The new `swift-huggingface` client (used by `mlx-swift-lm` 3.x) is built on `URLSession` download tasks with resume data support. Files already fully downloaded are skipped. However, a partially downloaded file may restart from the beginning depending on server support. In practice: if the user kills the app mid-download, already-completed files are not re-downloaded. The partially downloaded file restarts.

### Is the download cached? ✅ Yes

Downloaded model files are cached in the app's `Caches` directory under a Hugging Face path structure. They survive app restarts. They do NOT survive the user clearing app storage in Settings — in that case the download runs again.

### Does it need internet after download? ❌ No

Once fully downloaded, inference is 100% offline. No Hugging Face pings, no telemetry, nothing leaves the device.

---

## Required Entitlements

Add in Xcode → Signing & Capabilities for iOS and macOS targets:

**Increased Memory Limit** — required for loading model weights on device. Without this the model load will fail with a memory error on physical devices.

```
com.apple.developer.kernel.increased-memory-limit
```

Add it in Xcode under Signing & Capabilities → + Capability → "Increased Memory Limit".

**Outgoing Connections (Client)** — required for the one-time Hugging Face download.

Already covered by `NSAppTransportSecurity` / default iOS networking entitlements. No special capability needed — standard `URLSession` outgoing connections work by default.

---

## File Structure

Add these files to `SlateiOS/AI/`:

```
SlateiOS/AI/
  MLXModelManager.swift     # download state, progress, caching
  MLXInputParser.swift      # InputParserProtocol implementation
```

Update:
```
Shared/AI/
  ParserFactory.swift       # add MLX tier
```

---

## Implementation

### MLXModelManager.swift

Owns the download lifecycle. Persists download state across app launches via `UserDefaults`. Exposes `@Published` properties for the UI.

```swift
import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

@MainActor
final class MLXModelManager: ObservableObject {

    static let shared = MLXModelManager()

    // MARK: - Published state

    @Published private(set) var state: ModelState = .notDownloaded

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)   // 0.0 – 1.0
        case loading                         // weights in memory, not yet ready
        case ready
        case failed(String)
    }

    // MARK: - Private

    private let modelID = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    private var container: ModelContainer?

    private let stateKey = "slate.mlx.modelDownloaded"

    private init() {
        // Restore state on launch
        if UserDefaults.standard.bool(forKey: stateKey) {
            state = .notDownloaded  // will verify on prepare()
        }
    }

    // MARK: - Public API

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var isDownloaded: Bool {
        UserDefaults.standard.bool(forKey: stateKey)
    }

    /// Call on app launch if model was previously downloaded.
    /// Loads weights into memory silently in background.
    func prepareIfDownloaded() async {
        guard isDownloaded else { return }
        await loadIntoMemory()
    }

    /// Full download + load. Shows progress via `state` publisher.
    /// Safe to call multiple times — no-ops if already ready.
    func downloadAndLoad() async {
        guard !isReady else { return }

        do {
            state = .downloading(progress: 0)

            let config = ModelConfiguration(id: modelID)

            container = try await LLMModelFactory.shared.loadContainer(
                from: HubClient.default,
                using: TokenizersLoader(),
                configuration: config,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.state = .downloading(
                            progress: progress.fractionCompleted
                        )
                    }
                }
            )

            UserDefaults.standard.set(true, forKey: stateKey)
            state = .ready

        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Parse input using loaded model. Throws if model not ready.
    func generate(prompt: String) async throws -> String {
        guard let container else {
            throw MLXError.modelNotLoaded
        }

        let input = UserInput(prompt: .text(prompt))
        var result = ""

        let _ = try await container.perform { context in
            let prepared = try await context.processor.prepare(input: input)
            let stream = context.model.generate(
                input: prepared,
                parameters: .init(temperature: 0)
            )
            for try await token in stream {
                result += token
                // Stop at end of JSON to avoid over-generation
                if result.contains("}") { break }
            }
            return result
        }

        return result
    }

    // MARK: - Private

    private func loadIntoMemory() async {
        state = .loading
        do {
            let config = ModelConfiguration(id: modelID)
            container = try await LLMModelFactory.shared.loadContainer(
                from: HubClient.default,
                using: TokenizersLoader(),
                configuration: config
                // no progressHandler — silent background load
            )
            state = .ready
        } catch {
            // Model files corrupted or missing — reset and require re-download
            UserDefaults.standard.set(false, forKey: stateKey)
            state = .notDownloaded
        }
    }
}

enum MLXError: Error {
    case modelNotLoaded
    case parseError
}
```

### MLXInputParser.swift

Implements `InputParserProtocol`. Uses the same system prompt and JSON parsing logic as `CloudInputParser`.

```swift
import Foundation

final class MLXInputParser: InputParserProtocol {

    private let manager: MLXModelManager

    init(manager: MLXModelManager = .shared) {
        self.manager = manager
    }

    private let systemPrompt = """
    You are a financial input parser. Parse the user's message.
    Return ONLY a JSON object. No explanation, no markdown, no backticks.

    JSON schema:
    {
      "intent": "transaction" | "query",
      "amount": number | null,
      "currency": string | null,
      "description": string | null,
      "category": string | null,
      "queryCategory": string | null,
      "queryType": "income" | "expense" | null,
      "queryPeriod": "today" | "week" | "month" | "year" | "all" | null
    }

    Rules:
    - "bought","spent","paid" → negative amount (expense)
    - "received","salary","earned" → positive amount (income)
    - Ambiguous with no income word → expense
    - "show","see","how much","list" → query intent
    - Default queryPeriod to "month" if not specified
    - Default currency to TMT if not specified
    - Return null for unknown fields
    """

    func parse(input: String) async throws -> ParsedInput {
        guard manager.isReady else {
            throw MLXError.modelNotLoaded
        }

        let fullPrompt = """
        \(systemPrompt)

        User: \(input)
        JSON:
        """

        let raw = try await manager.generate(prompt: fullPrompt)
        return try decodeJSON(raw)
    }

    private func decodeJSON(_ raw: String) throws -> ParsedInput {
        // Extract JSON object from raw output
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip any accidental markdown
        text = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Find JSON boundaries
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }

        guard let data = text.data(using: .utf8) else {
            throw MLXError.parseError
        }

        return try JSONDecoder().decode(ParsedInput.self, from: data)
    }
}
```

### Updated ParserFactory.swift

```swift
import Foundation

enum ParserFactory {

    static func make() -> InputParserProtocol {

        // Tier 1: Foundation Models (iOS 26, A17 Pro+, Apple Intelligence enabled)
        if #available(iOS 26, *) {
            // FoundationModelsParser() — add when targeting iOS 26
            // import FoundationModels
            // if SystemLanguageModel.default.availability == .available {
            //     return FoundationModelsParser()
            // }
        }

        // Tier 2: MLX on-device (iOS 18+, Metal, model downloaded)
        if MLXModelManager.shared.isReady {
            return MLXInputParser()
        }

        // Tier 3: Cloud (Groq) — queued when offline
        return CloudInputParser()
    }
}
```

---

## Download UI

### When to trigger the download

Do **not** force the download on first launch. Show a prompt first — the user should consent to a 300MB download.

Trigger points:
1. First time the user submits input while offline → show download offer
2. Settings screen → "Enable offline parsing" toggle
3. Onboarding screen (optional) → "Download AI model for offline use"

### ModelDownloadView.swift

```swift
import SwiftUI

struct ModelDownloadView: View {

    @ObservedObject var manager: MLXModelManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.fill")
                .font(.system(size: 48))
                .foregroundStyle(.primary)

            Text("Download Offline AI")
                .font(.title2.weight(.semibold))

            Text("Download a 300MB model to parse your inputs without internet. This happens once and stores on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch manager.state {

            case .notDownloaded:
                Button("Download (~300MB)") {
                    Task { await manager.downloadAndLoad() }
                }
                .buttonStyle(.borderedProminent)

                Button("Not now") { onDismiss() }
                    .foregroundStyle(.secondary)

            case .downloading(let progress):
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.primary)

                    // Progress fires per-file, not per-byte
                    // so show step count, not percentage
                    Text("\(Int(progress * 100))% downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Don't close the app")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading model...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .ready:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready for offline use")
                        .font(.subheadline)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        onDismiss()
                    }
                }

            case .failed(let reason):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                    Text("Download failed")
                        .font(.subheadline.weight(.medium))
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await manager.downloadAndLoad() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .interactiveDismissDisabled(isDownloading)
    }

    private var isDownloading: Bool {
        if case .downloading = manager.state { return true }
        return false
    }
}
```

### Showing the download offer

In `MainView.swift`, detect when the user submits offline and no model is ready:

```swift
// In handleSubmit(), before queuing to PendingInput:
if !network.isConnected && !MLXModelManager.shared.isReady {
    // First offline attempt — offer the download
    showModelDownloadOffer = true
    // Still queue the input — don't lose it
    let pending = PendingInput(rawText: raw)
    modelContext.insert(pending)
    return
}
```

```swift
// In MainView body:
.sheet(isPresented: $showModelDownloadOffer) {
    ModelDownloadView(manager: MLXModelManager.shared) {
        showModelDownloadOffer = false
    }
}
```

---

## App Launch Flow

In `SlateIOSApp.swift`, silently prepare the model in the background if it was previously downloaded:

```swift
@main
struct SlateIOSApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .task {
                    // Silent background load — no UI, no blocking
                    await MLXModelManager.shared.prepareIfDownloaded()
                }
        }
        .modelContainer(for: [Transaction.self, PendingInput.self])
    }
}
```

This means:
- First ever launch → model not downloaded → `prepareIfDownloaded()` no-ops
- Subsequent launches → model already on disk → loads silently in background while user opens app
- By the time user types their first input, model is likely already in memory

---

## Updated ParserFactory with Full Tier Logic

```swift
enum ParserFactory {

    static func make() -> InputParserProtocol {

        // Tier 1: Foundation Models
        // Uncomment when targeting iOS 26:
        // if #available(iOS 26, *),
        //    SystemLanguageModel.default.availability == .available {
        //     return FoundationModelsParser()
        // }

        // Tier 2: MLX (model downloaded and loaded into memory)
        if MLXModelManager.shared.isReady {
            return MLXInputParser()
        }

        // Tier 3: Cloud
        return CloudInputParser()
    }

    // Call this after MLX model finishes downloading/loading
    // to hot-swap from Cloud to MLX without restarting
    static func currentParser(networkConnected: Bool) -> InputParserProtocol {
        if MLXModelManager.shared.isReady {
            return MLXInputParser()
        }
        if networkConnected {
            return CloudInputParser()
        }
        // Offline + no model = queue (caller handles this)
        return CloudInputParser()
    }
}
```

---

## InputViewModel Integration

In `InputViewModel` (your existing `@Observable` view model), update parser resolution so it switches to MLX automatically after download completes:

```swift
@Observable
final class InputViewModel {

    private var _parser: InputParserProtocol = ParserFactory.make()

    // Called after MLXModelManager.state becomes .ready
    func refreshParser() {
        _parser = ParserFactory.make()
    }
}
```

In `MainView`, observe `MLXModelManager.shared.state` and call `refreshParser()` when it becomes `.ready`:

```swift
.onChange(of: mlxManager.state) { _, new in
    if case .ready = new {
        inputViewModel.refreshParser()
    }
}
```

---

## Key Behaviors Summary

| Behavior | Detail |
|---|---|
| Download progress API | ✅ `progressHandler` closure with `Progress` object |
| Progress granularity | Per-file (not per-byte) — steps, not smooth |
| Resume on interruption | ✅ Completed files skipped, partial file may restart |
| Offline after download | ✅ 100% offline, no network calls during inference |
| Cached across launches | ✅ Cached in app's Caches directory |
| Survives app restart | ✅ Yes |
| Survives storage clear | ❌ No — re-download required |
| Cost | Free — Apache 2.0 model, no API key |
| Model size | ~300MB (Qwen2.5-0.5B-Instruct-4bit) |
| Runtime RAM | ~350MB |
| iPhone 11 compatible | ✅ Fits in 4GB RAM |
| Structured output | ❌ No `@Generable` — prompt-engineered JSON + manual decode |
| Speed on A13 (iPhone 11) | ~3 tok/sec — acceptable for 10–15 token inputs |
| Speed on A16+ | ~15–30 tok/sec |

---

## What's NOT Needed

- No Hugging Face account or token (public model)
- No API key of any kind
- No Python or model conversion steps
- No model bundled in the app (downloaded at runtime)
- No Obj-C++ bridging (pure Swift)

---

## Gotchas

**Progress fires per-file, not per-byte.** The model has ~6 files total. Progress jumps from 0% → 17% → 33% etc. Don't show a smooth progress bar — show step-based or indeterminate while between files.

**Model load time on first use.** Even after download, loading weights into GPU memory takes 3–8 seconds on iPhone 11. Show a loading state. `prepareIfDownloaded()` on app launch minimizes this by loading in the background before the user's first input.

**JSON output quality on 0.5B.** Small models occasionally malform JSON. The `decodeJSON` function in `MLXInputParser` handles the common cases (extra whitespace, accidental markdown). Add a retry with a stricter prompt if parsing fails — before falling back to cloud.

**GPU cache limit.** Set `MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)` before loading the model to prevent MLX from consuming all available GPU memory, which would affect the rest of the app.

```swift
import MLX

// Call once before first loadContainer
MLX.GPU.set(cacheLimit: 20 * 1024 * 1024) // 20MB cache limit
```

**watchOS.** Do not add MLX dependencies to the watchOS target. Watch parsing goes through the iPhone via WatchConnectivity as before — the iPhone's MLX parser handles it.
