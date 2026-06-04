import SwiftData
import Foundation

@Model
final class Transaction {
    var id: UUID
    var amount: Double
    var currency: String
    var desc: String
    var category: String
    var date: Date
    var rawInput: String

    init(
        amount: Double,
        currency: String,
        desc: String,
        category: TransactionCategory,
        rawInput: String,
        date: Date = .now
    ) {
        self.id = UUID()
        self.amount = amount
        self.currency = currency
        self.desc = desc
        self.category = category.rawValue
        self.date = date
        self.rawInput = rawInput
    }

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: category) ?? .other
    }
}
