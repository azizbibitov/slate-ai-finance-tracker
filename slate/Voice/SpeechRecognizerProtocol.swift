import Observation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case unavailable(String)
}

@MainActor
protocol SpeechRecognizerProtocol: AnyObject, Observable {
    var state: RecordingState { get }
    func toggle(onStart: @escaping () -> Void, onPartialResult: @escaping (String) -> Void)
    func stop()
}
