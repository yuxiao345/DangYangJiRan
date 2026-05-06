import Foundation
import SwiftData

protocol MerchantServiceProtocol {
    func createMerchant(_ merchant: Merchant, ledger: Ledger, context: ModelContext) throws
    func fetchMerchants(for ledger: Ledger, context: ModelContext) throws -> [Merchant]
    func updateMerchant(_ merchant: Merchant, context: ModelContext) throws
    func deleteMerchant(_ merchant: Merchant, context: ModelContext) throws
}
