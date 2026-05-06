import Foundation

extension Decimal {
    var isNegative: Bool {
        self < 0
    }

    var absoluteValue: Decimal {
        Swift.abs(self)
    }

    func formatted(
        currencyCode: String = "CNY",
        showSign: Bool = false
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let number = NSDecimalNumber(decimal: self)
        guard var result = formatter.string(from: number) else {
            return "\(self)"
        }

        if showSign, !isNegative {
            result = "+" + result
        }

        return result
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
