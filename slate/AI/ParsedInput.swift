import Foundation

struct ParsedInput: Codable, Sendable {

    enum Intent: String, Codable, Sendable {
        case transaction
        case query
        case transfer
        case createAccount
    }

    enum QueryType: String, Codable, Sendable {
        case income
        case expense
        case accounts
    }

    enum QueryPeriod: String, Codable, Sendable {
        case today
        case week
        case month
        case year
        case all
    }

    var intent: Intent

    // Transaction fields
    var amount: Double?
    var currency: String?
    var description: String?
    var category: TransactionCategory?

    // Query fields
    var queryCategory: TransactionCategory?
    var queryType: QueryType?
    var queryPeriod: QueryPeriod?
    var querySearch: String?      // keyword to match against description (person, place, note)

    // Transfer fields
    var sourceAccount: String?
    var destinationAccount: String?
    var exchangeRate: Double?
    var destinationAmount: Double?

    // Create account fields
    var accountName: String?
    var accountCurrency: String?
    var accountEmoji: String?
}
