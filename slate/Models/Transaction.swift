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

    // Account association (nil = no account)
    var accountID: UUID?

    // Transfer pair linkage (nil = not a transfer)
    var transferID: UUID?
    var counterpartAccountID: UUID?

    init(
        amount: Double,
        currency: String,
        desc: String,
        category: TransactionCategory,
        rawInput: String,
        date: Date = .now,
        accountID: UUID? = nil,
        transferID: UUID? = nil,
        counterpartAccountID: UUID? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.currency = currency
        self.desc = desc
        self.category = category.rawValue
        self.date = date
        self.rawInput = rawInput
        self.accountID = accountID
        self.transferID = transferID
        self.counterpartAccountID = counterpartAccountID
    }

    var transactionCategory: TransactionCategory {
        TransactionCategory(rawValue: category) ?? .other
    }

    var isTransfer: Bool { transferID != nil }
}
