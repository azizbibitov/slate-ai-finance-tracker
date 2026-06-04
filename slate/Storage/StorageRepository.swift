import Foundation

@MainActor
protocol StorageRepository: AnyObject {
    func insertTransaction(_ transaction: Transaction)
    func insertPending(_ pending: PendingInput)
    func deletePending(_ pending: PendingInput)
    func save() throws
    func fetchPending() -> [PendingInput]
    func fetchAllTransactions() -> [Transaction]
}
