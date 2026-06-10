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
            stop()
        } else if case .starting = state {
            // ignore taps while initializing
        } else {
            onStart()
            state = .starting
            Task { await start(onPartialResult: onPartialResult) }
        }
    }

    func stop() {
        sessionGeneration += 1
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
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
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            state = .unavailable("Speech recognition permission denied — check Settings")
            return
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            state = .unavailable("Microphone access needed for voice input")
            return
        }

        let candidates = [Locale.current, Locale(identifier: "en-US")]
        recognizer = candidates
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.isAvailable }

        guard recognizer != nil else {
            state = .unavailable("Voice not available for this language — please type")
            return
        }

        do {
            try beginAudioSession(onPartialResult: onPartialResult)
            if case .starting = state { state = .recording }
        } catch {
            if case .starting = state { state = .unavailable("Could not start recording") }
        }
    }

    private static let transcriptFixes: [(pattern: String, replacement: String)] = [
        // "minutes" is acoustically close to "manats"
        (#"\bminutes\b"#, "manats"),
        // "at work" / "atwork" mishearing of "Upwork"
        (#"\bat\s*work\b"#, "Upwork"),
    ]

    private static func fixTranscript(_ text: String) -> String {
        var result = text
        for fix in transcriptFixes {
            if let pattern = try? NSRegularExpression(pattern: fix.pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: fix.replacement)
            }
        }
        return result
    }

    // Runs entirely on the main actor. AVAudioEngine and the recognition request are
    // non-Sendable and are owned here and torn down in stop() — keeping them in one
    // isolation domain is what makes this data-race safe. There is no `await` in this
    // body, so stop() cannot interleave mid-setup; no generation guard is needed here.
    private func beginAudioSession(onPartialResult: @escaping (String) -> Void) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = [
            "manat", "manats", "TMT", "tmt",
            "dollar", "dollars", "USD",
            "euro", "euros", "EUR",
            "ruble", "rubles", "RUB",
            "salary", "taxi", "groceries", "coffee", "rent", "utilities",
            "Upwork", "Fiverr", "Toptal", "Freelancer"
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

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let engineStartTime = Date()

        // The tap block runs on CoreAudio's render thread, and append(_:) is designed to be
        // called from exactly there. The compiler can't see that contract, so we assert it:
        // the request is only appended-to here and ended in stop() — never mutated concurrently.
        nonisolated(unsafe) let tapRequest = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Skip first 300ms — hardware may deliver buffered audio from the previous session
            guard Date().timeIntervalSince(engineStartTime) > 0.3 else { return }
            tapRequest.append(buffer)
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine
    }
}
