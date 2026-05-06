import Foundation
import SwiftData

struct MerchantServiceImpl: MerchantServiceProtocol {
    func createMerchant(_ merchant: Merchant, ledger: Ledger, context: ModelContext) throws {
        merchant.ledger = ledger
        context.insert(merchant)
        try context.save()
    }

    func fetchMerchants(for ledger: Ledger, context: ModelContext) throws -> [Merchant] {
        let ledgerID = ledger.id
        let descriptor = FetchDescriptor<Merchant>(
            predicate: #Predicate { $0.ledger?.id == ledgerID },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    func updateMerchant(_ merchant: Merchant, context: ModelContext) throws {
        try context.save()
    }

    func deleteMerchant(_ merchant: Merchant, context: ModelContext) throws {
        context.delete(merchant)
        try context.save()
    }
}
