import Foundation

protocol CurrencyServiceProtocol {
    var supportedCurrencies: [String] { get }
    func format(amount: Decimal, currencyCode: String, showSign: Bool) -> String
    func symbol(for currencyCode: String) -> String
    func convert(
        amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String
    ) async throws -> Decimal?
}
