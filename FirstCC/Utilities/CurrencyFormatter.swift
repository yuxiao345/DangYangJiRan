import Foundation

struct CurrencyFormatter {
    static func format(
        amount: Decimal,
        currencyCode: String = "CNY",
        showSign: Bool = true
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let number = NSDecimalNumber(decimal: amount)
        guard var result = formatter.string(from: number) else {
            return "\(amount)"
        }

        if showSign, !amount.isNegative {
            result = "+" + result
        }

        return result
    }

    static func formatShort(
        amount: Decimal,
        currencyCode: String = "CNY"
    ) -> String {
        let absValue = amount.absoluteValue
        let sign = amount.isNegative ? "-" : ""

        if absValue >= 10000 {
            let wan = absValue / 10000
            let number = NSDecimalNumber(decimal: wan)
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 0
            if let formatted = formatter.string(from: number) {
                return "\(sign)\(formatted)万"
            }
        }

        return format(amount: amount, currencyCode: currencyCode, showSign: false)
    }

    static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}
