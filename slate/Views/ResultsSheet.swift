import SwiftUI

struct ResultsSheet: View {
    let result: QueryResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }

                if result.transactions.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        ForEach(result.transactions) { tx in
                            TransactionRowView(transaction: tx)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        }
                    } header: {
                        Text("TRANSACTIONS")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brand)
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brand)
                Text(result.originalQuery)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            if result.totalsByCurrency.isEmpty {
                Text("No transactions found")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(result.totalsByCurrency, id: \.currency) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(CurrencyFormatter.format(item.total, showSign: true))
                                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(item.total >= 0 ? Color.brand : Color.primary)
                            Text(item.currency)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 3)
                        }
                    }
                }
            }

            Text("\(result.transactions.count) transaction\(result.transactions.count == 1 ? "" : "s") · \(periodLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matching transactions")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Try a different period or category")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
}
