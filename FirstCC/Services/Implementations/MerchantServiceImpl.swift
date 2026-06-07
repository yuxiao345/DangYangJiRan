import Foundation
@preconcurrency import CoreData

struct MerchantServiceImpl: MerchantServiceProtocol {
    func createMerchant(_ merchant: Merchant, ledger: Ledger, context: NSManagedObjectContext) throws {
        merchant.ledger = ledger
        try context.save()
    }

    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Merchant? {
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "ledger.id == %@ AND name == %@", ledger.id as CVarArg, name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func fetchMerchants(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Merchant] {
        let ledgerID = ledger.id
        let request = NSFetchRequest<Merchant>(entityName: "Merchant")
        request.predicate = NSPredicate(format: "ledger.id == %@", ledgerID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "name", ascending: true)]
        let results = try context.fetch(request)
        let names = results.map(\.name)
        NSLog("[MerchantSvc] fetchMerchants count=\(results.count) names=\(names)")
        return results
    }

    func updateMerchant(_ merchant: Merchant, context: NSManagedObjectContext) throws {
        try context.save()
    }

    func deleteMerchant(_ merchant: Merchant, context: NSManagedObjectContext) throws {
        let name = merchant.name
        let id = merchant.id
        NSLog("[MerchantSvc] deleteMerchant name=\(name) id=\(id.uuidString.prefix(8))")
        context.delete(merchant)
        do {
            try context.save()
            NSLog("[MerchantSvc] deleteMerchant OK name=\(name)")
        } catch {
            context.rollback()
            NSLog("[MerchantSvc] deleteMerchant FAIL name=\(name): \(error.localizedDescription)")
            throw error
        }
    }
}
