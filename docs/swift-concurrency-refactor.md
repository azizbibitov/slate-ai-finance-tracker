# Swift Concurrency Refactor — Learning Guide

A hands-on, sequenced plan for adopting strict Swift Concurrency in Slate. This is a
**learning vehicle**, not just a cleanup. Each step is grounded in real code, explains the
*why*, and maps onto a skill you'll need for the Messaging WebSocket work later.

> Rule for this guide: do **one step at a time**. Build, read the diagnostics, understand
> them, fix, build again. Don't batch steps - the compiler errors are the curriculum.

---

## The starting reality

Current build settings (from `slate.xcodeproj/project.pbxproj`):

| Setting | Value | Meaning |
|---|---|---|
| `SWIFT_VERSION` | `5.0` | Swift 5 language mode - strict concurrency checking is at *minimal*. Data races compile silently. |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | Opted into newer "async work runs on the caller's actor" behavior. Good, but does **not** turn on diagnostics. |
| `SWIFT_STRICT_CONCURRENCY` | *(unset → minimal)* | The lever we flip in Step 0. |

So despite the CLAUDE.md/spec saying "Swift 6", the project is **not** enforcing data-race
safety yet. Turning it on is Step 0.

---

## Map of concurrency surfaces in Slate

| File | What it does | State today | Target |
|---|---|---|---|
| [SpeechRecognizer.swift](../slate/Voice/SpeechRecognizer.swift) | Bridges `SFSpeechRecognizer` callbacks, audio engine | `@MainActor`, but `Task.detached` shares non-`Sendable` AVF objects across domains | **Looked correct under minimal checking; wasn't.** Collapse to one domain (Step 1). |
| [InputParserProtocol.swift](../slate/AI/InputParserProtocol.swift) | Parser protocol | `AnyObject`, non-`Sendable` | `AnyObject & Sendable` |
| [GroqInputParser.swift](../slate/AI/Parsers/GroqInputParser.swift) | Network call to Groq | `final class`, immutable state, nonisolated | Confirm `Sendable`, no changes needed |
| [InputViewModel.swift](../slate/ViewModels/InputViewModel.swift) | App logic, `showToast` | `@MainActor @Observable` | Fix `showToast` task handle |
| [NetworkMonitor.swift](../slate/Network/NetworkMonitor.swift) | `NWPathMonitor` wrapper | Non-isolated, non-`Sendable`, mutable shared state, escaping closure | `@MainActor` + `AsyncStream<Bool>` |
| [QueueProcessor.swift](../slate/AI/QueueProcessor.swift) | Flush offline queue | `@MainActor`, sequential `for` loop | `TaskGroup` for parallel parse |
| [SwiftDataStorageRepository.swift](../slate/Storage/SwiftDataStorageRepository.swift) | SwiftData CRUD | `@MainActor` | No change (correct as-is) |

---

## Step 0 - Turn on the safety net

**Goal:** make the compiler show you every unsafe boundary.

**Do this in Xcode** (not by editing `project.pbxproj`):
Target → Build Settings → search "Strict Concurrency" → set
**Strict Concurrency Checking = Complete**, while leaving `SWIFT_VERSION` at 5.0.

**Why this and not Swift 6 mode yet:** in Swift 5 mode with `Complete` checking, isolation
violations come through as **warnings**, not errors. You get the full diagnostic surface
without a red build, so you can fix them incrementally. Once the warnings are all gone, flip
`SWIFT_VERSION` to 6 to lock it in - that promotion should then be a no-op.

**What to do:** build, then read the warnings *before changing any code*. Expect them
clustered around `SpeechRecognizer.beginAudioSession` (the `Task.detached` block),
`NetworkMonitor`, and the parser protocol. Sit with them. Each one names a real boundary where
a value or reference crosses between concurrency domains unsafely.

**Concepts to internalize here:** isolation domains, `Sendable`, what "crossing an actor
boundary" actually means.

**Done when:** you've read every warning and can describe, for each, *which* value crosses
*which* boundary.

---

## Step 1 - Worked example: collapse `SpeechRecognizer` to one domain

**Goal:** the lesson that *"compiles and works"* is not the same claim as *"data-race free"* -
and the most common real fix: stop splitting ownership of a non-`Sendable` object across two
isolation domains.

This one came straight out of Step 0. `SpeechRecognizer` *looked* like the reference example -
it already used `withCheckedContinuation`, a `sessionGeneration` cancellation token, and hopped
back to `@MainActor` correctly. Under minimal checking it was clean. Under `Complete`, the
`beginAudioSession` method produced four warnings. They all came from **one** mistake.

**The problem:** the method is `@MainActor`-isolated, but it spun up a `Task.detached` (the
*concurrent* executor - a different domain) to do the audio setup off the main thread. Two
non-`Sendable` Apple objects then straddled that boundary:

```swift
// BEFORE (abridged) — beginAudioSession was @MainActor but...
let currentRecognitionRequest = request            // also stored in self.recognitionRequest (main actor)
try await Task.detached(priority: .userInitiated) { // ...this runs on the concurrent executor
    let engine = AVAudioEngine()                     // engine is "task-isolated" to the detached task
    inputNode.installTap(onBus: 0, ...) { buffer, _ in
        currentRecognitionRequest.append(buffer)     // non-Sendable request captured into a `sending` closure
    }
    try engine.start()
    await MainActor.run { self.audioEngine = engine } // ...then `engine` is SENT to the main actor and stored
}.value
```

The four warnings, decoded:
1. `currentRecognitionRequest` is reachable from the main actor (via `self.recognitionRequest`)
   *and* captured by the `installTap` block (a `sending` closure that escapes to the audio
   thread). Same non-`Sendable` object, two domains.
2 & 3 & 4. `engine` is created in the detached task but stored on the main actor via
   `MainActor.run` - `AVAudioEngine` isn't `Sendable`, so the detached task and the main actor
   can race on it. *"Sending `engine` risks causing data races."*

The irony: the `Task.detached` existed to move work off-main, but that hop is the *only* reason
these objects crossed a boundary at all. And the `sessionGeneration` guard *inside* the detached
block existed solely to paper over the race window the hop opened.

**The fix:** own the engine and request entirely on the main actor - delete the `Task.detached`.
`beginAudioSession` becomes synchronous (`throws`, no `async`):

```swift
private func beginAudioSession(onPartialResult: @escaping (String) -> Void) throws {
    // ... build request, set recognitionTask (unchanged) ...

    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    try session.setActive(true, options: .notifyOthersOnDeactivation)
    #endif

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    let engineStartTime = Date()

    // The tap runs on CoreAudio's render thread, and append(_:) is designed to be called
    // from exactly there. The compiler can't see that contract, so we assert it.
    nonisolated(unsafe) let tapRequest = request
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        guard Date().timeIntervalSince(engineStartTime) > 0.3 else { return }
        tapRequest.append(buffer)
    }
    engine.prepare()
    try engine.start()
    audioEngine = engine            // never crosses a boundary now
}
```

**Why this is correct, not just quiet:**
- `engine` is created, stored, and (in `stop()`) torn down all on the main actor. It never
  crosses a domain, so warnings 2-4 are *structurally* gone, not suppressed.
- Because there's no `await` left in the body, `stop()` (also `@MainActor`) cannot interleave
  mid-setup. That deletes the entire `sessionGeneration`-guard-inside-the-detached-block dance.
- The one genuine cross-thread access that *remains* is the tap calling `request.append(_:)` on
  CoreAudio's render thread. That is the documented, designed usage of
  `SFSpeechAudioBufferRecognitionRequest`, and the type is internally synchronized for it. The
  compiler can't encode that contract, so `nonisolated(unsafe)` is the honest tool: it says "I
  know this non-`Sendable` value is touched off-actor and I'm asserting it's safe." Use it
  *only* when you can name the actual guarantee, as here - never to mute a warning you don't
  understand.

**The tradeoff:** `session.setActive` / `engine.start()` now run on the main thread. They're
normally single-digit-ms, but `setActive` can occasionally block longer during audio
negotiation with other apps. For a deliberate voice-button tap that's acceptable. If profiling
ever shows a hitch, the *right* fix is a dedicated `actor AudioEngineController` that owns the
engine for its whole lifecycle (setup **and** teardown) - same actor pattern as the Messaging
`WebSocketManager` - **not** a return to `Task.detached` with shared non-`Sendable` state.

**Concepts:** isolation-domain ownership, why splitting a non-`Sendable` object across domains
is the canonical mistake, `sending` closures, `nonisolated(unsafe)` as a *documented-contract*
escape hatch, and how removing an unnecessary async hop deletes the race-mitigation code it
required.

**Done when:** the four `beginAudioSession` warnings are gone, voice input still records and
transcribes, and you can state which single design choice (the `Task.detached`) caused all four.

---

## Step 2 - Sendable warm-up: the parser protocol

**Goal:** smallest possible real fix. Understand why an immutable reference type is safe to
share.

**The problem:** [InputParserProtocol.swift:13](../slate/AI/InputParserProtocol.swift) is:

```swift
protocol InputParserProtocol: AnyObject {
    func parse(input: String, context: ParserContext) async throws -> ParsedInput
}
```

It's stored as `any InputParserProtocol` inside two `@MainActor` types
([InputViewModel](../slate/ViewModels/InputViewModel.swift) and
[QueueProcessor](../slate/AI/QueueProcessor.swift)) and `parse` is awaited across the
boundary. A non-`Sendable` `any` type crossing that boundary is what strict mode flags.

**The fix:**

```swift
protocol InputParserProtocol: AnyObject, Sendable {
    func parse(input: String, context: ParserContext) async throws -> ParsedInput
}
```

**Why this is safe:** [GroqInputParser](../slate/AI/Parsers/GroqInputParser.swift) is a
`final class` whose every stored property is an immutable `let` (`apiKey`, `endpoint`,
`model`, `systemPrompt`). A class with only immutable, `Sendable` storage has no mutable
shared state to race on, so it legitimately conforms to `Sendable`. The compiler verifies
this for you - if someone later adds a `var`, the conformance breaks and you find out
immediately.

**Inputs/outputs are already clean:** `ParserContext` is `Sendable`
([InputParserProtocol.swift:3](../slate/AI/InputParserProtocol.swift)) and `ParsedInput` is
`Sendable` ([ParsedInput.swift:3](../slate/AI/ParsedInput.swift)). So the whole `parse`
signature is sendable-in / sendable-out. This matters for Step 5.

**Done when:** the protocol conforms to `Sendable`, `GroqInputParser` compiles without an
explicit conformance annotation (it's inferred), and the related warnings disappear.

---

## Step 3 - Task cancellation: `showToast`

**Goal:** structured vs unstructured tasks, and holding a cancellable handle.

**The problem:** [InputViewModel.swift:275](../slate/ViewModels/InputViewModel.swift):

```swift
private func showToast(_ text: String, isError: Bool = false) {
    toast = ToastMessage(text: text, isError: isError)
    Task {
        try? await Task.sleep(for: .seconds(2.5))
        if toast?.text == text { toast = nil }   // string-equality hack
    }
}
```

Every call spawns a new fire-and-forget `Task`. If two toasts fire within 2.5s, both timers
run; the `toast?.text == text` check is a workaround to stop the *first* timer from clearing
the *second* toast. It works, but it's coupling dismissal correctness to message text (two
identical messages break it) and leaking timer tasks.

**The fix:** keep a handle, cancel the previous timer.

```swift
private var toastDismissTask: Task<Void, Never>?

private func showToast(_ text: String, isError: Bool = false) {
    toast = ToastMessage(text: text, isError: isError)
    toastDismissTask?.cancel()
    toastDismissTask = Task {
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        toast = nil
    }
}
```

**Why:** `Task.sleep` throws `CancellationError` when the task is cancelled, so `try?`
swallows it and the `guard !Task.isCancelled` makes the intent explicit. Cancelling the
prior task means only the latest toast's timer is ever live. No text coupling, no leaked
tasks. Because `InputViewModel` is `@MainActor`, the `Task` closure inherits main-actor
isolation - reading/writing `toast` is safe with no hops.

**Concepts:** unstructured `Task`, cancellation propagation, `Task.isCancelled`,
actor-inherited task isolation.

**Done when:** rapid successive toasts never clear the wrong message, and there's a single
live dismiss task at a time.

---

## Step 4 - The keystone: `NetworkMonitor` → `AsyncStream`

**Goal:** safely bridge a callback-based system API that fires on a background queue into the
actor world. **This is the WebSocket-manager pattern in miniature** - the single most
transferable exercise in Slate.

**The problem:** [NetworkMonitor.swift](../slate/Network/NetworkMonitor.swift):

```swift
@Observable
final class NetworkMonitor {
    private(set) var isConnected = false
    var onConnectionRestored: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "slate.networkmonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = connected
                if connected && !wasConnected { self.onConnectionRestored?() }
            }
        }
        monitor.start(queue: queue)
    }
    deinit { monitor.cancel() }
}
```

Three distinct race hazards strict mode will flag:
1. The class is **not** isolated and **not** `Sendable`, yet `pathUpdateHandler` is a
   `@Sendable` escaping closure that captures `self`. `NWPathMonitor` invokes it on the
   `slate.networkmonitor` background queue.
2. `isConnected` is **nonisolated mutable state**. It's written inside the `@MainActor` Task
   but the property itself has no isolation, so it's also readable from the background queue
   and from `InputViewModel` on the main actor with no synchronization. Classic torn-read
   race.
3. `onConnectionRestored` is a **mutable, non-`Sendable` closure property** set from one
   context ([InputViewModel.setup](../slate/ViewModels/InputViewModel.swift):46) and invoked
   from another. The callback style also means the consumer can only register *one* handler.

**The target design:** make the type `@MainActor` so its observable state is main-isolated
(SwiftUI reads it on the main actor anyway), and replace the `onConnectionRestored` callback
with an `AsyncStream<Bool>` that the consumer can `for await` over.

```swift
import Network
import Foundation

@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = false

    /// Emits the connection state on every change. Consumers `for await` over this.
    let connectionChanges: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "slate.networkmonitor")

    init() {
        (connectionChanges, continuation) = AsyncStream.makeStream()

        // pathUpdateHandler runs on a background queue. The ONLY thing we do there is
        // yield into the continuation - and AsyncStream.Continuation is Sendable, so this
        // crosses the boundary safely with no captured mutable self-state.
        monitor.pathUpdateHandler = { [continuation] path in
            continuation.yield(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    /// Call once after init (from a @MainActor context) to keep `isConnected` in sync and
    /// react to changes. Returns when the stream finishes.
    func observe(onConnectionRestored: @escaping @MainActor () -> Void) async {
        for await connected in connectionChanges {
            let wasConnected = isConnected
            isConnected = connected
            if connected && !wasConnected { onConnectionRestored() }
        }
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
```

**Why this is the right shape:**
- The background closure now captures **only** the `continuation`, which is `Sendable` by
  design. There's no `self`, no mutable shared state crossing the queue boundary - the race
  is structurally impossible, not just avoided.
- `isConnected` is now main-actor isolated. Every reader (SwiftUI, `InputViewModel.submit`)
  is already on the main actor, so reads are free and safe.
- The `AsyncStream` decouples production (background `NWPathMonitor` callback) from
  consumption (a main-actor `for await` loop). This is exactly how you'll drain a WebSocket's
  `receive()` results into your UI later.

**Consumer side** - update
[InputViewModel.setup](../slate/ViewModels/InputViewModel.swift):41:

```swift
func setup(storage: any StorageRepository) {
    guard queueProcessor == nil else { return }
    self.storage = storage
    let processor = QueueProcessor(parser: parser, storage: storage)
    queueProcessor = processor

    Task { [weak self, weak processor] in
        await self?.networkMonitor.observe {
            Task { await processor?.flushQueue() }
        }
    }
}
```

**Design discussion - why `@MainActor` and not an `actor`:** an `actor NetworkMonitor` is the
other valid answer, and it's worth understanding the tradeoff:
- `@MainActor` wins here because the *only* consumer is the UI layer, which is already
  main-isolated. Making it an `actor` would force an `await` on every `isConnected` read from
  SwiftUI and complicate `@Observable` integration. No benefit, more friction.
- An `actor` wins when state is contended by *multiple non-UI* callers and you want it off the
  main thread. **That's the WebSocket manager case** - many message sends/receives, reconnect
  timers, none of which should touch the main thread. So when you build that, reach for
  `actor`. Slate's `NetworkMonitor` teaches the `AsyncStream` bridge; the Messaging app
  teaches the same bridge *inside* an `actor`.

**Concepts:** `@MainActor` isolation on a type, `AsyncStream` + `Continuation`, `Sendable`
continuations as a safe boundary-crossing primitive, actor-vs-MainActor judgment, structured
consumption with `for await`.

**Done when:** zero concurrency warnings in `NetworkMonitor`, the offline queue still flushes
when connectivity returns, and you can explain why capturing only the continuation removes the
race.

---

## Step 5 - Structured concurrency: `TaskGroup` in `QueueProcessor`

**Goal:** parallelize independent I/O, then serialize the shared-state mutation. Learn *when*
parallelism is safe and when it isn't.

**The current code:** [QueueProcessor.swift:22](../slate/AI/QueueProcessor.swift) parses
pending items one at a time:

```swift
for item in pending {
    do {
        let parsed = try await parser.parse(input: item.rawText, context: context)
        // ... insert / delete / mutate retryCount ...
    } catch { ... }
}
```

If 8 inputs queued offline, this makes 8 network round-trips **sequentially**. They're
independent - each `parse` only needs the item's `rawText` and the shared (immutable)
`context`. That's a fan-out opportunity.

**The critical constraint:** the *parse* is parallelizable, but the *persistence* is not.
`ModelContext` and the `@Model` types (`PendingInput`, `Transaction`) are `@MainActor` and
non-`Sendable`. You **cannot** insert/delete/mutate them off the main actor. So the pattern is:

> Fan out the `Sendable` network work in a `TaskGroup`, collect `Sendable` results, then apply
> all mutations back on the main actor in a serial pass.

```swift
func flushQueue() async {
    let pending = storage.fetchPending()
    guard !pending.isEmpty else { return }

    let context = ParserContext(accounts: storage.fetchAllAccounts().map {
        ParserContext.AccountInfo(name: $0.name, currency: $0.currency, isDefault: $0.isDefault)
    })

    // Result must be Sendable to leave the task. Carry the array index + parsed payload.
    struct ParseOutcome: Sendable {
        let index: Int
        let parsed: ParsedInput?   // nil = parse failed
    }

    let outcomes = await withTaskGroup(of: ParseOutcome.self) { group in
        for (index, item) in pending.enumerated() {
            let raw = item.rawText            // copy the Sendable String out; don't capture the @Model
            group.addTask {
                let parsed = try? await self.parser.parse(input: raw, context: context)
                return ParseOutcome(index: index, parsed: parsed)
            }
        }
        var collected: [ParseOutcome] = []
        for await outcome in group { collected.append(outcome) }
        return collected
    }

    // Back on the main actor (we never left it for mutation): apply results serially.
    for outcome in outcomes {
        let item = pending[outcome.index]
        if let parsed = outcome.parsed,
           let tx = makeTransaction(from: parsed, raw: item.rawText, date: item.entryDate) {
            storage.insertTransaction(tx)
            storage.deletePending(item)
        } else {
            item.retryCount += 1
            item.status = .failed
        }
    }
    try? storage.save()
}
```

**Why the closure captures `raw` and not `item`:** `PendingInput` is a non-`Sendable`
`@MainActor` model. Capturing it in an `addTask` closure (which runs off the main actor) is
exactly the kind of escape strict mode forbids. Pulling the `Sendable` `String` out *before*
the task closure keeps the model on the main actor. The index lets you re-associate the
result with its model afterward.

**Judgment call - is this worth it?** For a typical offline queue of 1-3 items, the
sequential version is fine and simpler. The reason to do it here is **to learn the pattern**,
and because a queue that built up over a long offline stretch genuinely benefits. Note the
honest tradeoff: parallel requests hit the Groq rate limit harder, and ordering of inserts
changes (mitigated by re-walking `pending` in order for the mutation pass). If you want to
cap concurrency, that's the next refinement (a `TaskGroup` with a sliding window of N
in-flight tasks) - a good follow-up exercise.

**Concepts:** `withTaskGroup`, `Sendable` result types, why you copy values out before
`addTask`, structured concurrency's "all child tasks complete before the group returns"
guarantee, fan-out/fan-in.

**Done when:** the queue still flushes correctly (test by queueing several inputs offline,
then restoring connectivity), no model escapes a task, and you can articulate why persistence
stayed on the main actor.

---

## Step 6 - Lock it in

**Goal:** promote to full Swift 6 mode.

Once Steps 0-5 leave you with **zero** concurrency warnings under `Complete` checking, flip
`SWIFT_VERSION` to `6.0` in Build Settings. If the earlier steps were done right, this is a
no-op - the warnings you already fixed are the errors Swift 6 mode would raise. If anything
new appears, it's a spot where a warning was being downgraded; fix it the same way.

**Done when:** the project builds clean in Swift 6 language mode.

---

## After Slate: carrying this to the Messaging app

Every step here is deliberate prep for the WebSocket work:

| Slate exercise | Messaging app payoff |
|---|---|
| Step 1 - one-domain ownership + `nonisolated(unsafe)` | Owning a non-`Sendable` socket/engine in one place; asserting documented thread-safety contracts |
| Step 2 - `Sendable` protocol | Message/event payloads crossing the socket boundary |
| Step 3 - task cancellation | Cancel the receive loop / reconnect timer on disconnect |
| Step 4 - `AsyncStream` bridge | Drain `URLSessionWebSocketTask.receive()` into the UI safely |
| Step 4 - actor vs MainActor | The WebSocket manager **is** the `actor` case |
| Step 5 - `TaskGroup` | Parallel metadata fetch (Movie Streaming app) |

The one thing Slate can't teach is the `actor` itself - its only stateful background citizen
(`NetworkMonitor`) is best as `@MainActor`. So treat the Messaging `WebSocketManager` actor as
the direct sequel: same `AsyncStream` bridge, same cancellation, but now wrapped in an `actor`
with a `.disconnected → .connecting → .connected` state machine.

---

## Quick reference - the mental models

- **Isolation domain:** a region of code guaranteed to run serially (a given actor, or
  `@MainActor`). Crossing between domains is where races live.
- **`Sendable`:** a type safe to hand across a domain boundary. Value types of `Sendable`
  members, immutable-only classes, and actors qualify.
- **`AsyncStream`:** a one-way pipe from any producer (even a C callback on a random thread)
  to an `async` consumer. The `Continuation` is `Sendable`, which is what makes it the clean
  bridge out of callback land.
- **`TaskGroup`:** structured fan-out. Children must return `Sendable` values; the group
  awaits all of them. Copy non-`Sendable` data out *before* `addTask`.
- **`@MainActor` vs `actor`:** `@MainActor` for state the UI owns and reads directly; `actor`
  for state contended by background work that shouldn't block the main thread.
- **`nonisolated(unsafe)`:** an escape hatch that opts a declaration out of isolation checking.
  Legitimate only when you can name the real thread-safety guarantee the compiler can't see
  (e.g. `SFSpeechAudioBufferRecognitionRequest.append` is built for the audio render thread).
  Never a way to silence a warning you don't understand.
- **Compiles ≠ race-free:** minimal checking proves neither. Only `Complete`/Swift 6 mode
  distinguishes "works today" from "has no data races" - Step 1 is the case study.
