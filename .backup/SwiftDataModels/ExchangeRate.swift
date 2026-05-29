import Foundation
import SwiftData

@Model
final class ExchangeRate {
    var id: UUID = UUID()
    var fromCurrencyCode: String = ""
    var toCurrencyCode: String = ""
    var rate: Decimal = 0
    var fetchedAt: Date = Date()

    init(
        id: UUID = UUID(),
        fromCurrencyCode: String,
        toCurrencyCode: String,
        rate: Decimal,
        fetchedAt: Date = Date()
    ) {
        self.id = id
        self.fromCurrencyCode = fromCurrencyCode
        self.toCurrencyCode = toCurrencyCode
        self.rate = rate
        self.fetchedAt = fetchedAt
    }
}
