import SwiftUI
import SwiftData

enum FeedTab {
    case expense
    case income
}

enum FeedPeriod: CaseIterable {
    case day, week, month, year

    var label: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }

    func start(from now: Date, cal: Calendar) -> Date {
        switch self {
        case .day:   return cal.startOfDay(for: now)
        case .week:  return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
        case .month: return cal.date(from: cal.dateComponents([.year, .month], from: now))!
        case .year:  return cal.date(from: cal.dateComponents([.year], from: now))!
        }
    }

    func headerLabel(from now: Date) -> String {
        switch self {
        case .day:   return "Today"
        case .week:  return "Last 7 days"
        case .month: return now.formatted(.dateTime.month(.wide))
        case .year:  return now.formatted(.dateTime.year())
        }
    }
}

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

private struct DateGroup: Identifiable {
    let id: String
    let title: String
    let sortDate: Date
    let items: [FeedItem]
}

struct FeedView: View {
    let tab: FeedTab
    @Binding var selectedTab: FeedTab
    @Binding var selectedPeriod: FeedPeriod

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \PendingInput.entryDate, order: .reverse) private var pendingInputs: [PendingInput]
    @Environment(InputViewModel.self) private var vm
    @Environment(\.modelContext) private var modelContext

    private var periodStart: Date {
        selectedPeriod.start(from: Date(), cal: Calendar.current)
    }

    private var feedItems: [FeedItem] {
        var items: [FeedItem] = []

        var transferGroups: [UUID: [Transaction]] = [:]
        var regular: [Transaction] = []
        for tx in transactions where tx.date >= periodStart {
            if let tid = tx.transferID {
                transferGroups[tid, default: []].append(tx)
            } else {
                regular.append(tx)
            }
        }

        let filtered = regular.filter { tab == .expense ? $0.amount < 0 : $0.amount > 0 }
        items.append(contentsOf: filtered.map { .transaction($0) })

        if tab == .expense {
            for (_, pair) in transferGroups {
                if pair.count == 2,
                   let source = pair.first(where: { $0.amount < 0 }),
                   let dest = pair.first(where: { $0.amount > 0 }) {
                    items.append(.transfer(source: source, destination: dest))
                }
            }
        }

        items.append(contentsOf: pendingInputs.map { .pending($0) })
        return items.sorted { $0.date > $1.date }
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

            tabSwitcher

            Spacer().frame(height: 14)

            periodPicker

            Spacer().frame(height: 20)

            if periodTotals.isEmpty {
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
                    ForEach(Array(periodTotals.enumerated()), id: \.offset) { idx, item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(CurrencyFormatter.format(item.total))
                                .font(.system(size: idx == 0 ? 52 : 26,
                                              weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(tab == .income ? Color.brand : Color.primary)
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

    // MARK: - Tab switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabPill(label: "Expenses", tab: .expense)
            tabPill(label: "Income", tab: .income)
        }
        .padding(3)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tabPill(label: String, tab: FeedTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(duration: 0.25)) { selectedTab = tab }
        } label: {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(isSelected ? (tab == .income ? Color.brand : Color.primary) : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? AnyShapeStyle(Color(.systemBackground).shadow(.drop(color: .black.opacity(0.07), radius: 4, y: 2)))
                        : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack(spacing: 6) {
            ForEach(FeedPeriod.allCases, id: \.label) { period in
                periodChip(period)
            }
        }
    }

    private func periodChip(_ period: FeedPeriod) -> some View {
        let isSelected = selectedPeriod == period
        return Button {
            withAnimation(.spring(duration: 0.2)) { selectedPeriod = period }
        } label: {
            Text(period.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.brand : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.brandMuted : Color(.secondarySystemBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed totals / footer

    private var periodTotals: [(currency: String, total: Double)] {
        transactions
            .filter {
                $0.date >= periodStart &&
                (tab == .expense ? $0.amount < 0 : $0.amount > 0) &&
                $0.transferID == nil
            }
            .reduce(into: [:] as [String: Double]) { $0[$1.currency, default: 0] += abs($1.amount) }
            .map { (currency: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private var footerText: String {
        let now = Date()
        let periodLabel = selectedPeriod.headerLabel(from: now)
        let count = transactions.filter {
            $0.date >= periodStart &&
            (tab == .expense ? $0.amount < 0 : $0.amount > 0) &&
            $0.transferID == nil
        }.count
        if count == 0 { return periodLabel }
        let word = tab == .expense
            ? (count == 1 ? "expense" : "expenses")
            : (count == 1 ? "income entry" : "income entries")
        return "\(periodLabel) · \(count) \(word)"
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
                Text(tab == .expense ? "No expenses" : "No income")
                    .font(.system(.headline, design: .rounded))
                Text("for \(selectedPeriod.headerLabel(from: Date()).lowercased())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}
