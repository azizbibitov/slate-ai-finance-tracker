import SwiftData
import Foundation

@Model
final class Account {
    var id: UUID
    var name: String
    var currency: String
    var emoji: String
    var sortOrder: Int
    var isArchived: Bool
    var isDefault: Bool

    init(name: String, currency: String, emoji: String = "💳", sortOrder: Int = 0, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.currency = currency
        self.emoji = emoji
        self.sortOrder = sortOrder
        self.isArchived = false
        self.isDefault = isDefault
    }
}
