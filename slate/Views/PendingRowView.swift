import SwiftUI

struct PendingRowView: View {
    let pending: PendingInput
    @Environment(InputViewModel.self) private var vm

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pending.status == .failed ? "exclamationmark.circle" : "clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(pending.status == .failed ? .red : .secondary)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(pending.rawText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(pending.entryDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if pending.status == .failed {
                Button("Retry") {
                    Task { await vm.retryFailed(pending) }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Text("Queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
