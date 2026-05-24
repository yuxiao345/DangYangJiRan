import Foundation
@preconcurrency import CoreData

struct MerchantServiceImpl: MerchantServiceProtocol {
    func createMerchant(_ merchant: Merchant, ledger: Ledger, context: NSManagedObjectContext) throws {
        merchant.ledger = ledger
        try context.save()
    }

    func fetchMerchants(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Merchant] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }

    func updateMerchant(_ merchant: Merchant, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteMerchant(_ merchant: Merchant, context: NSManagedObjectContext) throws {
        context.delete(merchant)
        try context.save()
    }
}
