import Foundation

protocol ExchangeRateServiceProtocol {
    func fetchRate(from: String, to: String) async throws -> ExchangeRate
    func cachedRate(from: String, to: String) -> ExchangeRate?
    func refreshRates() async throws
}
