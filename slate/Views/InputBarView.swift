import SwiftUI

struct InputBarView: View {
    @Environment(InputViewModel.self) private var vm

    @FocusState private var isFocused: Bool
    var body: some View {
        @Bindable var vm = vm

        VStack(spacing: 0) {
            Divider()
                .opacity(0.4)

            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                HStack(spacing: 10) {
                    MicButton(speechRecognizer: vm.speechRecognizer) {
                        vm.inputText = ""
                    } onTranscript: { transcript in
                        vm.inputText = transcript
                    }

                    TextField("Log a transaction or ask...", text: $vm.inputText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                        .onChange(of: isFocused) { _, now in
                            print("[FOCUS] isFocused = \(now)")
                        }
                        .onSubmit { Task { await vm.submit() } }

                    SendButton(vm: vm)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .background(.regularMaterial)
            .animation(.spring(duration: 0.2), value: vm.errorMessage == nil)
        }
    }
}

// MARK: - Mic

private struct MicButton: View {
    let speechRecognizer: any SpeechRecognizerProtocol
    let onStart: () -> Void
    let onTranscript: (String) -> Void

    var body: some View {
        Button {
            speechRecognizer.toggle(onStart: onStart, onPartialResult: onTranscript)
        } label: {
            ZStack {
                if case .recording = speechRecognizer.state {
                    PulseRing()
                }
                Circle()
                    .fill(micBackground)
                    .frame(width: 40, height: 40)
                if case .starting = speechRecognizer.state {
                    ProgressView()
                        .tint(.secondary)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: micIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(micColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(speechRecognizer.state == .starting)
    }

    private var micIcon: String {
        switch speechRecognizer.state {
        case .recording:       return "waveform"
        case .unavailable:     return "mic.slash"
        default:               return "mic"
        }
    }

    private var micColor: Color {
        if case .recording = speechRecognizer.state { return .red }
        return .secondary
    }

    private var micBackground: Color {
        if case .recording = speechRecognizer.state { return Color.red.opacity(0.10) }
        return Color(.tertiarySystemBackground)
    }
}

private struct PulseRing: View {
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .stroke(Color.red.opacity(opacity), lineWidth: 2)
            .frame(width: 52, height: 52)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    scale = 1.55
                    opacity = 0
                }
            }
    }
}

// MARK: - Send

private struct SendButton: View {
    let vm: InputViewModel

    private var isEmpty: Bool {
        vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Button {
            Task { await vm.submit() }
        } label: {
            ZStack {
                Circle()
                    .fill(isEmpty ? Color(.tertiarySystemBackground) : Color.brand)
                    .frame(width: 40, height: 40)
                if vm.isProcessing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: vm.networkMonitor.isConnected ? "arrow.up" : "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isEmpty ? Color(.tertiaryLabel) : .white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isEmpty || vm.isProcessing)
        .animation(.spring(duration: 0.2), value: isEmpty)
    }
}
