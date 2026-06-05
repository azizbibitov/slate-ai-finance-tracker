import SwiftData
import Foundation

@MainActor
final class SwiftDataStorageRepository: StorageRepository {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func insertTransaction(_ transaction: Transaction) { context.insert(transaction) }
    func insertPending(_ pending: PendingInput) { context.insert(pending) }
    func deletePending(_ pending: PendingInput) { context.delete(pending) }
    func insertAccount(_ account: Account) { context.insert(account) }
    func deleteAccount(_ account: Account) { context.delete(account) }

    func save() throws { try context.save() }

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

    func fetchAllAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchDefaultAccount() -> Account? {
        fetchAllAccounts().first { $0.isDefault } ?? fetchAllAccounts().first
    }

    func setDefaultAccount(_ account: Account) {
        for a in fetchAllAccounts() { a.isDefault = false }
        account.isDefault = true
        try? context.save()
    }
}
