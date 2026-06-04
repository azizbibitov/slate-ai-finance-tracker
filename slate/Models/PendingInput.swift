import SwiftData
import Foundation

@Model
final class PendingInput {
    var id: UUID
    var rawText: String
    var entryDate: Date
    var retryCount: Int
    var statusRaw: String

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    enum Status: String, Codable {
        case pending
        case failed
    }

    init(rawText: String) {
        self.id = UUID()
        self.rawText = rawText
        self.entryDate = .now
        self.retryCount = 0
        self.statusRaw = Status.pending.rawValue
    }
}
