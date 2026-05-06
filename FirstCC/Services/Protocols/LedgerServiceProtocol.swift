import Foundation
import SwiftData

protocol LedgerServiceProtocol {
    func createLedger(name: String, type: LedgerType, currencyCode: String, context: ModelContext) throws -> Ledger
    func fetchLedgers(context: ModelContext) throws -> [Ledger]
    func updateLedger(_ ledger: Ledger, context: ModelContext) throws
    func deleteLedger(_ ledger: Ledger, context: ModelContext) throws
    func switchToLedger(_ ledger: Ledger)
}
