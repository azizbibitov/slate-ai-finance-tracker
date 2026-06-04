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

private struct DateGroup: Identifiable {
    let id: String
    let title: String
    let sortDate: Date
    let items: [FeedItem]
}

struct FeedView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \PendingInput.entryDate, order: .reverse) private var pendingInputs: [PendingInput]
    @Environment(InputViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext

    private var feedItems: [FeedItem] {
        let txItems = transactions.map(FeedItem.transaction)
        let pendingItems = pendingInputs.map(FeedItem.pending)
        return (txItems + pendingItems).sorted { $0.date > $1.date }
    }

    private var groupedItems: [DateGroup] {
        let calendar = Calendar.current
        let dict = Dictionary(grouping: feedItems) { item in
            calendar.startOfDay(for: item.date)
        }
        return dict.map { day, items -> DateGroup in
            let title: String
            if calendar.isDateInToday(day)          { title = "Today" }
            else if calendar.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
            return DateGroup(id: title, title: title, sortDate: day,
                             items: items.sorted { $0.date > $1.date })
        }
        .sorted { $0.sortDate > $1.sortDate }
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
                ForEach(groupedItems) { group in
                    Section {
                        ForEach(group.items) { item in
                            switch item {
                            case .transaction(let tx):
                                TransactionRowView(transaction: tx)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                    .listRowSeparatorTint(Color(.separator).opacity(0.5))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(tx)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            case .pending(let p):
                                PendingRowView(pending: p)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                    .listRowSeparatorTint(Color(.separator).opacity(0.5))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(p)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Balance header

    private var balanceHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("slate")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 5) {
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

            Spacer().frame(height: 18)

            if thisMonthNets.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("0")
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.quaternary)
                    Text("TMT")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.quaternary)
                        .padding(.bottom, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(thisMonthNets.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(CurrencyFormatter.format(item.net, showSign: true))
                                .font(.system(size: idx == 0 ? 52 : 26,
                                              weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(item.net >= 0 ? Color.brand : Color.primary)
                            Text(item.currency)
                                .font(.system(size: idx == 0 ? 20 : 13,
                                              weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, idx == 0 ? 4 : 2)
                        }
                    }
                }
            }

            Spacer().frame(height: 6)

            Text(footerText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var thisMonthNets: [(currency: String, net: Double)] {
        let cal = Calendar.current
        let now = Date()
        return transactions
            .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(into: [:] as [String: Double]) { $0[$1.currency, default: 0] += $1.amount }
            .map { (currency: $0.key, net: $0.value) }
            .sorted { abs($0.net) > abs($1.net) }
    }

    private var footerText: String {
        let cal = Calendar.current
        let now = Date()
        let monthName = now.formatted(.dateTime.month(.wide))
        let count = transactions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }.count
        if count == 0 { return monthName }
        return "\(monthName) · \(count) \(count == 1 ? "entry" : "entries")"
    }

    // MARK: - Section header

    private func sectionHeader(_ group: DateGroup) -> some View {
        HStack(alignment: .center) {
            Text(group.title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            Text("\(group.items.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.brand.opacity(0.5))
            VStack(spacing: 5) {
                Text("Start tracking")
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
