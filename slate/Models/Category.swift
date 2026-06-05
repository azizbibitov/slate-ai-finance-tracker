import Foundation
import SwiftUI

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

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransactionCategory(rawValue: raw) ?? .other
    }

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

    var color: Color {
        switch self {
        case .food:          return .orange
        case .transport:     return .blue
        case .salary:        return Color.brand
        case .shopping:      return .purple
        case .health:        return .pink
        case .utilities:     return .yellow
        case .entertainment: return .indigo
        case .rent:          return Color(red: 0.6, green: 0.4, blue: 0.2)
        case .transfer:      return .secondary
        case .other:         return .secondary
        }
    }
}
