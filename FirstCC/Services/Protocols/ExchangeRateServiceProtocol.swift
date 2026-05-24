import Foundation
@preconcurrency import CoreData

protocol ExchangeRateServiceProtocol {
    func fetchRate(from: String, to: String, context: NSManagedObjectContext) async throws -> ExchangeRate
    func cachedRate(from: String, to: String, context: NSManagedObjectContext) -> ExchangeRate?
    func refreshRates() async throws
}
