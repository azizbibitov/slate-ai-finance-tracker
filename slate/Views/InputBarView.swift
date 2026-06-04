import SwiftUI

struct InputBarView: View {
    @Environment(InputViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var vm = vm

        VStack(alignment: .leading, spacing: 4) {
            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                MicButton(speechRecognizer: vm.speechRecognizer, onStart: {
                    vm.inputText = ""
                }, onTranscript: { transcript in
                    vm.inputText = transcript
                })

                TextField("e.g. -50 tmt taxi", text: $vm.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                    .onSubmit { Task { await vm.submit(modelContext: modelContext) } }

                Button {
                    Task { await vm.submit(modelContext: modelContext) }
                } label: {
                    Image(systemName: vm.isProcessing ? "ellipsis" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue.opacity(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.3 : 1.0))
                }
                .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isProcessing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

private struct MicButton: View {
    let speechRecognizer: SpeechRecognizer
    let onStart: () -> Void
    let onTranscript: (String) -> Void

    var body: some View {
        VStack(spacing: 2) {
            Button {
                speechRecognizer.toggle(onStart: onStart, onPartialResult: onTranscript)
            } label: {
                ZStack {
                    if case .starting = speechRecognizer.state {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(color)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .disabled(speechRecognizer.state == .starting)
            if case .unavailable(let msg) = speechRecognizer.state {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var icon: String {
        switch speechRecognizer.state {
        case .recording:            return "stop.circle.fill"
        case .unavailable:          return "mic.slash"
        case .idle, .starting:      return "mic"
        }
    }

    private var color: Color {
        switch speechRecognizer.state {
        case .recording:                        return .red
        case .unavailable, .idle, .starting:   return .secondary
        }
    }
}
