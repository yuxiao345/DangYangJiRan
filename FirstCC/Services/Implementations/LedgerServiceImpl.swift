import Foundation
import SwiftData

struct LedgerServiceImpl: LedgerServiceProtocol {
    func createLedger(name: String, type: LedgerType, currencyCode: String, context: ModelContext) throws -> Ledger {
        let ledger = Ledger(name: name, type: type, defaultCurrencyCode: currencyCode)
        context.insert(ledger)
        try context.save()
        return ledger
    }

    func fetchLedgers(context: ModelContext) throws -> [Ledger] {
        let descriptor = FetchDescriptor<Ledger>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    func updateLedger(_ ledger: Ledger, context: ModelContext) throws {
        try context.save()
    }

    func deleteLedger(_ ledger: Ledger, context: ModelContext) throws {
        context.delete(ledger)
        try context.save()
    }

    func switchToLedger(_ ledger: Ledger) {
        // Handled by AppContainer
    }
}
