import SwiftUI

struct TransferRowView: View {
    let source: Transaction
    let destination: Transaction

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(source.desc)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .lineLimit(1)
                Text("Transfer · " + source.date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(CurrencyFormatter.format(abs(source.amount), showSign: false)) \(source.currency)")
                    .font(.system(.caption, design: .rounded).monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(source.currency != destination.currency ? Color.brand : .secondary)
                    Text("\(CurrencyFormatter.format(destination.amount, showSign: false)) \(destination.currency)")
                        .font(.system(.caption, design: .rounded).monospacedDigit().weight(.semibold))
                        .foregroundStyle(source.currency != destination.currency ? Color.brand : .secondary)
                }
            }
        }
        .padding(.vertical, 11)
    }
}
