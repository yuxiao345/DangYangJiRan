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
        formatter.usesGroupingSeparator = true
        formatter.currencySymbol = simpleCurrencySymbol(for: currencyCode)

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

    private static func simpleCurrencySymbol(for code: String) -> String {
        switch code {
        case "USD", "AUD", "CAD", "SGD": return "$"
        case "CNY", "JPY": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        case "HKD": return "HK$"
        case "TWD": return "NT$"
        default:
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = code
            return f.currencySymbol ?? code
        }
    }

    static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}
