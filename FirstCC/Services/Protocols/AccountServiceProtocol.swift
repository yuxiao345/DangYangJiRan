import Foundation
@preconcurrency import CoreData

protocol AccountServiceProtocol {
    func createAccount(_ account: Account, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchAccounts(for ledger: Ledger, includeArchived: Bool, context: NSManagedObjectContext) throws -> [Account]
    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Account?
    func updateAccount(_ account: Account, context: NSManagedObjectContext) throws
    func deleteAccount(_ account: Account, context: NSManagedObjectContext) throws
    func calculateBalance(for account: Account, context: NSManagedObjectContext) -> Decimal
    /// 截至 `cutoff`（**不含** `cutoff` 当天）的余额；口径同 `calculateBalance(for:context:)`，
    /// 只多一条日期上界。用于反推月初净资产。
    func calculateBalance(for account: Account, before cutoff: Date, context: NSManagedObjectContext) -> Decimal
    func archiveAccount(_ account: Account, context: NSManagedObjectContext) throws
}

extension AccountServiceProtocol {
    func fetchAccounts(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Account] {
        try fetchAccounts(for: ledger, includeArchived: false, context: context)
    }
}
