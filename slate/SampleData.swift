import Foundation
import SwiftData

/// Demo / presentation data.
///
/// Seeds a realistic set of wallets and transactions into an *empty* store so
/// the app looks lived-in for a demo. It only runs when there are no accounts
/// yet, so it never duplicates or clobbers real data.
///
/// To ship without sample data: delete this file and remove the
/// `SampleData.seedIfNeeded(...)` call in `ContentView`.
enum SampleData {

    /// Seeds only if the store has no accounts yet.
    static func seedIfNeeded(_ context: ModelContext) {
        let hasAccounts = !((try? context.fetch(FetchDescriptor<Account>()))?.isEmpty ?? true)
        guard !hasAccounts else { return }
        seed(context)
    }

    /// Wipes all demo entities and reseeds. Handy to reset between demo runs.
    static func reset(_ context: ModelContext) {
        for t in (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] { context.delete(t) }
        for a in (try? context.fetch(FetchDescriptor<Account>())) ?? [] { context.delete(a) }
        for p in (try? context.fetch(FetchDescriptor<PendingInput>())) ?? [] { context.delete(p) }
        seed(context)
    }

    // MARK: - Seed

    static func seed(_ context: ModelContext) {
        let cal = Calendar.current
        let now = Date()

        /// A date `daysAgo` in the past, set to a specific hour/minute.
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        // MARK: Wallets
        let cash = Account(name: "Cash",     currency: "TMT", emoji: "👛", sortOrder: 0, isDefault: true)
        let card = Account(name: "Halkbank", currency: "TMT", emoji: "🏦", sortOrder: 1)
        let usd  = Account(name: "Dollars",  currency: "USD", emoji: "💵", sortOrder: 2)
        [cash, card, usd].forEach(context.insert)

        // MARK: Transaction helper
        func tx(_ amount: Double, _ currency: String, _ desc: String,
                _ category: TransactionCategory, _ account: Account, _ date: Date) {
            context.insert(Transaction(
                amount: amount, currency: currency, desc: desc, category: category,
                rawInput: desc, date: date, accountID: account.id
            ))
        }

        // MARK: Income (funds the wallets)
        tx( 8000, "TMT", "Salary",          .salary, cash, at(3, 10, 0))
        tx( 6000, "TMT", "Paycheck",        .salary, card, at(4, 11, 0))
        tx(  650, "USD", "Upwork project",  .salary, usd,  at(10, 16, 30))
        tx( 8000, "TMT", "Salary",          .salary, cash, at(33, 10, 0))
        tx(  500, "USD", "Upwork project",  .salary, usd,  at(40, 15, 0))

        // MARK: Today (drives the feed)
        tx(  -18, "TMT", "Coffee",          .food,          cash, at(0, 8, 10))
        tx(  -45, "TMT", "Taxi to office",  .transport,     cash, at(0, 9, 30))
        tx(  -85, "TMT", "Lunch",           .food,          card, at(0, 13, 15))
        tx( -260, "TMT", "Groceries",       .shopping,      card, at(0, 17, 40))
        tx( -120, "TMT", "Cinema",          .entertainment, cash, at(0, 19, 0))

        // MARK: Today - a transfer (USD -> Cash at 1 USD = 19.5 TMT)
        seedTransfer(context,
                     from: usd, fromAmount: 100, fromCurrency: "USD",
                     to: cash, toAmount: 1950, toCurrency: "TMT",
                     date: at(0, 12, 0))

        // MARK: This week
        tx( -180, "TMT", "Dinner",          .food,        cash, at(1, 20, 15))
        tx(  -75, "TMT", "Pharmacy",        .health,      card, at(1, 12, 30))
        tx(  -10, "TMT", "Bus",             .transport,   cash, at(1, 8, 45))
        tx( -340, "TMT", "Groceries",       .shopping,    card, at(2, 18, 0))
        tx( -200, "TMT", "Internet bill",   .utilities,   card, at(3, 14, 0))
        tx( -150, "TMT", "Gym membership",  .health,      cash, at(4, 9, 0))
        tx(  -90, "TMT", "Gift",            .shopping,    cash, at(5, 16, 20))
        tx( -130, "TMT", "Fuel",            .transport,   card, at(6, 11, 10))

        // MARK: Earlier this month
        tx(-3000, "TMT", "Rent",            .rent,          cash, at(8, 9, 0))
        tx( -220, "TMT", "Electricity",     .utilities,     card, at(9, 13, 0))
        tx( -210, "TMT", "Restaurant",      .food,          card, at(11, 20, 0))
        tx( -480, "TMT", "Clothes",         .shopping,      card, at(14, 15, 30))
        tx( -300, "TMT", "Doctor visit",    .health,        cash, at(16, 10, 30))
        tx( -250, "TMT", "Concert tickets", .entertainment, cash, at(19, 19, 0))
        tx( -390, "TMT", "Groceries",       .shopping,      card, at(22, 17, 0))
        tx(  -12, "USD", "App subscription",.entertainment, usd,  at(24, 8, 0))

        // MARK: Last month (so "year" / "all" queries have depth)
        tx(-3000, "TMT", "Rent",            .rent,      cash, at(34, 9, 0))
        tx( -260, "TMT", "Groceries",       .shopping,  card, at(36, 18, 0))
        tx( -140, "TMT", "Taxi",            .transport, cash, at(41, 22, 0))
        tx( -180, "TMT", "Utilities",       .utilities, card, at(45, 12, 0))

        try? context.save()
    }

    // MARK: - Transfer pair

    private static func seedTransfer(_ context: ModelContext,
                                     from source: Account, fromAmount: Double, fromCurrency: String,
                                     to dest: Account, toAmount: Double, toCurrency: String,
                                     date: Date) {
        let transferID = UUID()
        context.insert(Transaction(
            amount: -fromAmount, currency: fromCurrency, desc: "To \(dest.name)",
            category: .transfer, rawInput: "transfer", date: date,
            accountID: source.id, transferID: transferID, counterpartAccountID: dest.id
        ))
        context.insert(Transaction(
            amount: toAmount, currency: toCurrency, desc: "From \(source.name)",
            category: .transfer, rawInput: "transfer", date: date,
            accountID: dest.id, transferID: transferID, counterpartAccountID: source.id
        ))
    }
}
