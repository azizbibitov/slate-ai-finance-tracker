import Speech
import AVFoundation

@Observable
@MainActor
final class SpeechRecognizer: SpeechRecognizerProtocol {

    private(set) var state: RecordingState = .idle

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var sessionGeneration = 0

    func toggle(onStart: @escaping () -> Void, onPartialResult: @escaping (String) -> Void) {
        if case .recording = state {
            print("[Slate] Voice: stopping")
            stop()
        } else if case .starting = state {
            // ignore taps while initializing
        } else {
            print("[Slate] Voice: starting - thread: \(Thread.isMainThread ? "main" : "bg")")
            onStart()
            state = .starting
            Task { await start(onPartialResult: onPartialResult) }
        }
    }

    func stop() {
        print("[Slate] Voice: stop() — thread: \(Thread.isMainThread ? "main" : "bg")")
        sessionGeneration += 1
        let t = Date()
        audioEngine?.inputNode.removeTap(onBus: 0)
        print("[Slate] Voice: removeTap \(Date().timeIntervalSince(t))s")
        audioEngine?.stop()
        print("[Slate] Voice: audioEngine.stop() \(Date().timeIntervalSince(t))s")
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        state = .idle
    }

    private func start(onPartialResult: @escaping (String) -> Void) async {
        let t = Date()
        print("[Slate] Voice: requesting speech auth")
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        print("[Slate] Voice: speech auth done (\(Date().timeIntervalSince(t))s): \(speechStatus.rawValue)")
        guard speechStatus == .authorized else {
            state = .unavailable("Speech recognition permission denied — check Settings")
            return
        }

        print("[Slate] Voice: requesting mic permission")
        let micGranted = await AVAudioApplication.requestRecordPermission()
        print("[Slate] Voice: mic permission done (\(Date().timeIntervalSince(t))s): \(micGranted)")
        guard micGranted else {
            state = .unavailable("Microphone access needed for voice input")
            return
        }

        // Prefer device locale, fall back to English
        let candidates = [Locale.current, Locale(identifier: "en-US")]
        recognizer = candidates
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.isAvailable }
        print("[Slate] Voice: recognizer ready (\(Date().timeIntervalSince(t))s)")

        guard recognizer != nil else {
            state = .unavailable("Voice not available for this language — please type")
            return
        }

        do {
            print("[Slate] Voice: starting audio session")
            try await beginAudioSession(onPartialResult: onPartialResult)
            print("[Slate] Voice: audio session started (\(Date().timeIntervalSince(t))s)")
            // Guard: stop() may have been called while beginAudioSession was awaiting
            if case .starting = state { state = .recording }
        } catch {
            print("[Slate] Voice error: \(error)")
            if case .starting = state { state = .unavailable("Could not start recording") }
        }
    }

    // "minutes" is acoustically close to "manats" — in a finance app, "minutes" as a
    // standalone word always means the currency, never time duration.
    private static func fixTranscript(_ text: String) -> String {
        let pattern = try? NSRegularExpression(pattern: #"\bminutes\b"#, options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)
        return pattern?.stringByReplacingMatches(in: text, range: range, withTemplate: "manats") ?? text
    }

    private func beginAudioSession(onPartialResult: @escaping (String) -> Void) async throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [
            "manat", "manats", "TMT", "tmt",
            "dollar", "dollars", "USD",
            "euro", "euros", "EUR",
            "ruble", "rubles", "RUB",
            "salary", "taxi", "groceries", "coffee", "rent", "utilities"
        ]
        recognitionRequest = request

        let generation = sessionGeneration
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = Self.fixTranscript(result.bestTranscription.formattedString)
                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
                    onPartialResult(text)
                    if result.isFinal { self.stop() }
                }
            }
            if error != nil {
                Task { @MainActor in
                    guard self.sessionGeneration == generation else { return }
                    self.stop()
                }
            }
        }

        // Audio session setup and engine start are slow — run off main actor
        let currentRecognitionRequest = request
        try await Task.detached(priority: .userInitiated) { [generation] in
            #if os(iOS)
            let t2 = Date()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[Slate] Voice: AVAudioSession.setActive \(Date().timeIntervalSince(t2))s")
            #endif

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            let engineStartTime = Date()
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                // Skip first 300ms — hardware may deliver buffered audio from the previous session
                guard Date().timeIntervalSince(engineStartTime) > 0.3 else { return }
                currentRecognitionRequest.append(buffer)
            }
            engine.prepare()
            print("[Slate] Voice: engine.prepare() done")
            try engine.start()
            print("[Slate] Voice: engine.start() done")

            await MainActor.run {
                // stop() may have been called while the engine was starting on the background thread.
                // If so, audioEngine is still nil and stop() never cleaned it up — do it here instead.
                guard self.sessionGeneration == generation else {
                    engine.inputNode.removeTap(onBus: 0)
                    engine.stop()
                    #if os(iOS)
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    #endif
                    return
                }
                self.audioEngine = engine
            }
        }.value
    }
}
