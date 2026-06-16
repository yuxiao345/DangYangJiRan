import Foundation
@preconcurrency import CoreData

protocol AccountServiceProtocol {
    func createAccount(_ account: Account, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchAccounts(for ledger: Ledger, includeArchived: Bool, context: NSManagedObjectContext) throws -> [Account]
    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Account?
    func updateAccount(_ account: Account, context: NSManagedObjectContext) throws
    func deleteAccount(_ account: Account, context: NSManagedObjectContext) throws
    func calculateBalance(for account: Account, context: NSManagedObjectContext) -> Decimal
    func archiveAccount(_ account: Account, context: NSManagedObjectContext) throws
}

extension AccountServiceProtocol {
    func fetchAccounts(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Account] {
        try fetchAccounts(for: ledger, includeArchived: false, context: context)
    }
}
