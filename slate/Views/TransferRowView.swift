import SwiftUI

struct TransferRowView: View {
    let source: Transaction
    let destination: Transaction

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(source.desc)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Transfer · " + source.date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(CurrencyFormatter.format(abs(source.amount), showSign: false)) \(source.currency)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                if source.currency != destination.currency {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.brand)
                        Text("\(CurrencyFormatter.format(destination.amount, showSign: false)) \(destination.currency)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Color.brand)
                    }
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(destination.desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}
