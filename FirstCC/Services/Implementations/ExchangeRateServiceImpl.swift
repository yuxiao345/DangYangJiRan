import Foundation
@preconcurrency import CoreData

struct ExchangeRateServiceImpl: ExchangeRateServiceProtocol {

    /// Free, no-key exchange rate API
    private let baseURL = "https://api.frankfurter.app"

    func fetchRate(from: String, to: String, context: NSManagedObjectContext) async throws -> ExchangeRate {
        guard from != to else {
            return ExchangeRate(fromCurrencyCode: from, toCurrencyCode: to, rate: 1, context: context)
        }
        let url = URL(string: "\(baseURL)/latest?from=\(from)&to=\(to)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct Response: Decodable {
            let rates: [String: Decimal]
        }
        let decoder = JSONDecoder()
        let response = try decoder.decode(Response.self, from: data)
        guard let rate = response.rates[to] else {
            throw ExchangeRateError.rateNotFound(from, to)
        }
        return ExchangeRate(fromCurrencyCode: from, toCurrencyCode: to, rate: Double(truncating: rate as NSDecimalNumber), context: context)
    }

    func cachedRate(from: String, to: String, context: NSManagedObjectContext) -> ExchangeRate? {
        guard from != to else {
            return ExchangeRate(fromCurrencyCode: from, toCurrencyCode: to, rate: 1, context: context)
        }
        // Caching handled by SwiftData persistence — caller stores fetched rates
        return nil
    }

    func refreshRates() async throws {
        // No-op: rates are fetched on-demand per conversion
    }
}

enum ExchangeRateError: LocalizedError {
    case rateNotFound(String, String)

    var errorDescription: String? {
        switch self {
        case .rateNotFound(let from, let to): return String(localized: "未找到 \(from)→\(to) 汇率")
        }
    }
}
