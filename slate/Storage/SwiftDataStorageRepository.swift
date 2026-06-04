import SwiftData
import Foundation

@MainActor
final class SwiftDataStorageRepository: StorageRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insertTransaction(_ transaction: Transaction) {
        context.insert(transaction)
    }

    func insertPending(_ pending: PendingInput) {
        context.insert(pending)
    }

    func deletePending(_ pending: PendingInput) {
        context.delete(pending)
    }

    func save() throws {
        try context.save()
    }

    func fetchPending() -> [PendingInput] {
        let status = PendingInput.Status.pending.rawValue
        let descriptor = FetchDescriptor<PendingInput>(
            predicate: #Predicate { $0.statusRaw == status },
            sortBy: [SortDescriptor(\.entryDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchAllTransactions() -> [Transaction] {
        (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    }
}
