import SwiftUI
import SwiftData

private enum FeedItem: Identifiable {
    case transaction(Transaction)
    case transfer(source: Transaction, destination: Transaction)
    case pending(PendingInput)

    var id: UUID {
        switch self {
        case .transaction(let t):   return t.id
        case .transfer(let s, _):   return s.id
        case .pending(let p):       return p.id
        }
    }

    var date: Date {
        switch self {
        case .transaction(let t):   return t.date
        case .transfer(let s, _):   return s.date
        case .pending(let p):       return p.entryDate
        }
    }
}

struct FeedView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \PendingInput.entryDate, order: .reverse) private var pendingInputs: [PendingInput]
    @Environment(InputViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var feedItems: [FeedItem] {
        var items: [FeedItem] = []

        var transferGroups: [UUID: [Transaction]] = [:]
        var regular: [Transaction] = []
        for tx in transactions where tx.date >= todayStart {
            if let tid = tx.transferID {
                transferGroups[tid, default: []].append(tx)
            } else {
                regular.append(tx)
            }
        }

        items.append(contentsOf: regular.map { .transaction($0) })

        for (_, pair) in transferGroups {
            if pair.count == 2,
               let source = pair.first(where: { $0.amount < 0 }),
               let dest = pair.first(where: { $0.amount > 0 }) {
                items.append(.transfer(source: source, destination: dest))
            } else {
                items.append(contentsOf: pair.map { .transaction($0) })
            }
        }

        items.append(contentsOf: pendingInputs.map { .pending($0) })
        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                balanceHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20))
            }

            if feedItems.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            } else {
                Section {
                    ForEach(feedItems) { item in
                        switch item {
                        case .transaction(let tx):
                            TransactionRowView(transaction: tx)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparatorTint(Color(.separator).opacity(0.5))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        modelContext.delete(tx)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        case .transfer(let source, let dest):
                            TransferRowView(source: source, destination: dest)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparatorTint(Color(.separator).opacity(0.5))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        modelContext.delete(source)
                                        modelContext.delete(dest)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        case .pending(let p):
                            PendingRowView(pending: p)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowSeparatorTint(Color(.separator).opacity(0.5))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        modelContext.delete(p)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Balance header

    private var balanceHeader: some View {
        HStack {
            Text(footerText)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.tertiary)
            Spacer()
            aiBadge
        }
    }

    private var aiBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.brand)
                .frame(width: 5, height: 5)
            Text("AI")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.brand)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.brandMuted, in: Capsule())
    }

    // MARK: - Footer

    private var footerText: String {
        let count = transactions.filter { $0.date >= todayStart && $0.transferID == nil }.count
        let today = Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if count == 0 { return today }
        return "\(today) · \(count) \(count == 1 ? "entry" : "entries")"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.brand.opacity(0.5))
            VStack(spacing: 5) {
                Text("Nothing logged today")
                    .font(.system(.headline, design: .rounded))
                Text("Type or speak a transaction below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
