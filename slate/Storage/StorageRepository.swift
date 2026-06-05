import Foundation

@MainActor
protocol StorageRepository: AnyObject {
    func insertTransaction(_ transaction: Transaction)
    func insertPending(_ pending: PendingInput)
    func deletePending(_ pending: PendingInput)
    func insertAccount(_ account: Account)
    func deleteAccount(_ account: Account)
    func save() throws
    func fetchPending() -> [PendingInput]
    func fetchAllTransactions() -> [Transaction]
    func fetchAllAccounts() -> [Account]
    func fetchDefaultAccount() -> Account?
    func setDefaultAccount(_ account: Account)
}
