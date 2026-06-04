import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    private var isIncome: Bool { transaction.amount >= 0 }
    private var category: TransactionCategory { transaction.transactionCategory }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isIncome ? Color.brandMuted : Color(.tertiarySystemBackground))
                    .frame(width: 44, height: 44)
                Image(systemName: category.sfSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isIncome ? Color.brand : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.desc)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(category.rawValue.capitalized + " · " + transaction.date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.format(transaction.amount, showSign: true))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isIncome ? Color.brand : Color.primary)
                Text(transaction.currency)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}
