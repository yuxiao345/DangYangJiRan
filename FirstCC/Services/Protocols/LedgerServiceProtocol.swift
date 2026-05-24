import Foundation
@preconcurrency import CoreData

protocol LedgerServiceProtocol {
    func createLedger(name: String, type: LedgerType, currencyCode: String, context: NSManagedObjectContext) throws -> Ledger
    func fetchLedgers(context: NSManagedObjectContext) throws -> [Ledger]
    func updateLedger(_ ledger: Ledger, context: NSManagedObjectContext) throws
    func deleteLedger(_ ledger: Ledger, context: NSManagedObjectContext) throws
    func switchToLedger(_ ledger: Ledger)
}
