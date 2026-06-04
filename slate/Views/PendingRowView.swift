import SwiftUI

struct PendingRowView: View {
    let pending: PendingInput
    @Environment(InputViewModel.self) private var vm

    private var isFailed: Bool { pending.status == .failed }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isFailed ? Color.red.opacity(0.10) : Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: isFailed ? "exclamationmark.circle.fill" : "clock.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isFailed ? Color.red : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(pending.rawText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(pending.entryDate.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isFailed {
                Button {
                    Task { await vm.retryFailed(pending) }
                } label: {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brandMuted, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Queued")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground), in: Capsule())
            }
        }
        .padding(.vertical, 10)
    }
}
