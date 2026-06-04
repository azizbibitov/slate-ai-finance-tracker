import SwiftUI

struct TransactionRowView: View {
    let transaction: Transaction

    private var isIncome: Bool { transaction.amount >= 0 }

    private var amountText: String {
        let abs = abs(transaction.amount)
        let formatted = abs == abs.rounded() ? "\(Int(abs))" : String(format: "%.2f", abs)
        return (isIncome ? "+" : "-") + formatted
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.transactionCategory.sfSymbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isIncome ? .green : .primary)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.desc)
                    .font(.body)
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(amountText) \(transaction.currency)")
                .font(.body.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(isIncome ? .green : .primary)
        }
        .padding(.vertical, 4)
    }
}
