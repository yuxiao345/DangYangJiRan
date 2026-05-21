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
        let symbol = simpleCurrencySymbol(for: currencyCode.isEmpty ? "CNY" : currencyCode)

        if absValue >= 10000 {
            let wan = absValue / 10000
            let number = NSDecimalNumber(decimal: wan)
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 1
            formatter.minimumFractionDigits = 0
            if let formatted = formatter.string(from: number) {
                return "\(sign)\(symbol)\(formatted)万"
            }
        }

        let number = NSDecimalNumber(decimal: absValue)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        if let formatted = formatter.string(from: number) {
            return "\(sign)\(symbol)\(formatted)"
        }
        return "\(sign)\(symbol)0"
    }

    static func formatDecimal(
        amount: Decimal,
        fractionDigits: Int = 2,
        showAbs: Bool = false
    ) -> String {
        let value = showAbs ? amount.absoluteValue : amount
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = true
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
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
