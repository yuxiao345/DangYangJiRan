import Foundation
@preconcurrency import CoreData

struct LedgerServiceImpl: LedgerServiceProtocol {
    func createLedger(name: String, type: LedgerType, currencyCode: String, context: NSManagedObjectContext) throws -> Ledger {
        let ledger = Ledger(name: name, type: type, defaultCurrencyCode: currencyCode, context: context)
        try context.save()
        return ledger
    }

    func fetchLedgers(context: NSManagedObjectContext) throws -> [Ledger] {
        let request = NSFetchRequest<Ledger>(entityName: "Ledger")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    func updateLedger(_ ledger: Ledger, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteLedger(_ ledger: Ledger, context: NSManagedObjectContext) throws {
        context.delete(ledger)
        try context.save()
    }

    func switchToLedger(_ ledger: Ledger) {
        // Handled by AppContainer
    }
}
