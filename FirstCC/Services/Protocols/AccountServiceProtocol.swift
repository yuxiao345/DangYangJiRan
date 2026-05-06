import Foundation
import SwiftData

protocol AccountServiceProtocol {
    func createAccount(_ account: Account, ledger: Ledger, context: ModelContext) throws
    func fetchAccounts(for ledger: Ledger, context: ModelContext) throws -> [Account]
    func updateAccount(_ account: Account, context: ModelContext) throws
    func deleteAccount(_ account: Account, context: ModelContext) throws
    func calculateBalance(for account: Account, context: ModelContext) -> Decimal
    func archiveAccount(_ account: Account, context: ModelContext) throws
}
