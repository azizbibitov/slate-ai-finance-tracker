import Foundation

struct ParsedInput: Codable, Sendable {

    enum Intent: String, Codable, Sendable {
        case transaction
        case query
    }

    enum QueryType: String, Codable, Sendable {
        case income
        case expense
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
}
