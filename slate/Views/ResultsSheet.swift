import SwiftUI

struct ResultsSheet: View {
    let result: QueryResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryHeader
                Divider()
                if result.transactions.isEmpty {
                    emptyState
                } else {
                    List(result.transactions) { tx in
                        TransactionRowView(transaction: tx)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.originalQuery)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if result.totalsByCurrency.isEmpty {
                Text("No transactions")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(result.totalsByCurrency, id: \.currency) { item in
                    Text(formatTotal(item.total) + " " + item.currency)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(item.total >= 0 ? Color.green : Color.primary)
                }
            }

            Text("\(result.transactions.count) transaction\(result.transactions.count == 1 ? "" : "s") · \(periodLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No matching transactions")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try a different period or category")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var periodLabel: String {
        switch result.period {
        case .today: return "today"
        case .week:  return "past 7 days"
        case .month: return "this month"
        case .year:  return "this year"
        case .all:   return "all time"
        }
    }

    private func formatTotal(_ amount: Double) -> String {
        let abs = Swift.abs(amount)
        let sign = amount >= 0 ? "+" : "-"
        let formatted = abs == abs.rounded() ? "\(Int(abs))" : String(format: "%.2f", abs)
        return sign + formatted
    }
}
