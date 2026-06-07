import Foundation
@preconcurrency import CoreData

protocol MerchantServiceProtocol {
    func createMerchant(_ merchant: Merchant, ledger: Ledger, context: NSManagedObjectContext) throws
    func fetchMerchants(for ledger: Ledger, context: NSManagedObjectContext) throws -> [Merchant]
    func findByName(_ name: String, ledger: Ledger, context: NSManagedObjectContext) throws -> Merchant?
    func updateMerchant(_ merchant: Merchant, context: NSManagedObjectContext) throws
    func deleteMerchant(_ merchant: Merchant, context: NSManagedObjectContext) throws
}
