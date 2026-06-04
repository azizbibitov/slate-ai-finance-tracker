import Foundation

enum TransactionCategory: String, CaseIterable, Codable, Sendable {
    case food
    case transport
    case salary
    case shopping
    case health
    case utilities
    case entertainment
    case rent
    case transfer
    case other

    var sfSymbol: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .salary:        return "briefcase.fill"
        case .shopping:      return "bag.fill"
        case .health:        return "heart.fill"
        case .utilities:     return "bolt.fill"
        case .entertainment: return "gamecontroller.fill"
        case .rent:          return "house.fill"
        case .transfer:      return "arrow.left.arrow.right"
        case .other:         return "circle.fill"
        }
    }
}
