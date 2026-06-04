import SwiftUI
import SwiftData

private enum FeedItem: Identifiable {
    case transaction(Transaction)
    case pending(PendingInput)

    var id: UUID {
        switch self {
        case .transaction(let t): return t.id
        case .pending(let p): return p.id
        }
    }

    var date: Date {
        switch self {
        case .transaction(let t): return t.date
        case .pending(let p): return p.entryDate
        }
    }
}

struct FeedView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \PendingInput.entryDate, order: .reverse) private var pendingInputs: [PendingInput]
    @Environment(InputViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext

    private var items: [FeedItem] {
        let txItems = transactions.map(FeedItem.transaction)
        let pendingItems = pendingInputs.map(FeedItem.pending)
        return (txItems + pendingItems).sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                List(items) { item in
                    switch item {
                    case .transaction(let tx):
                        TransactionRowView(transaction: tx)
                            .listRowSeparator(.hidden)
                    case .pending(let p):
                        PendingRowView(pending: p)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No entries yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Type something like \"-50 tmt taxi\"")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
