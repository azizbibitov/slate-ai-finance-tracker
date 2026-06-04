import Foundation

struct QueryResult: Identifiable {
    let id = UUID()
    let originalQuery: String
    let transactions: [Transaction]
    let period: ParsedInput.QueryPeriod
    let filterCategory: TransactionCategory?
    let filterType: ParsedInput.QueryType?

    var totalsByCurrency: [(currency: String, total: Double)] {
        Dictionary(grouping: transactions, by: \.currency)
            .map { (currency: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { abs($0.total) > abs($1.total) }
    }
}

enum QueryFilter {
    static func run(query: ParsedInput, transactions: [Transaction], originalText: String) -> QueryResult {
        var filtered = transactions

        let now = Date()
        let cal = Calendar.current
        if let start = periodStart(query.queryPeriod ?? .month, from: now, cal: cal) {
            filtered = filtered.filter { $0.date >= start }
        }

        if let type_ = query.queryType {
            filtered = filtered.filter { type_ == .income ? $0.amount > 0 : $0.amount < 0 }
        }

        if let cat = query.queryCategory {
            filtered = filtered.filter { $0.transactionCategory == cat }
        }

        return QueryResult(
            originalQuery: originalText,
            transactions: filtered,
            period: query.queryPeriod ?? .month,
            filterCategory: query.queryCategory,
            filterType: query.queryType
        )
    }

    private static func periodStart(_ period: ParsedInput.QueryPeriod, from date: Date, cal: Calendar) -> Date? {
        switch period {
        case .today:  return cal.startOfDay(for: date)
        case .week:   return cal.date(byAdding: .weekOfYear, value: -1, to: date)
        case .month:  return cal.date(from: cal.dateComponents([.year, .month], from: date))
        case .year:   return cal.date(from: cal.dateComponents([.year], from: date))
        case .all:    return nil
        }
    }
}
