import Foundation

struct CurrencyFormatter {

    static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f
    }()

    private static let shortWanFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 0
        return f
    }()

    private static let shortIntegerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f
    }()

    private static let decimalCustomFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        return f
    }()

    private static let symbolFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f
    }()

    static func format(
        amount: Decimal,
        currencyCode: String = "CNY",
        showSign: Bool = true
    ) -> String {
        let formatter = currencyFormatter
        formatter.currencyCode = currencyCode
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
            if let formatted = shortWanFormatter.string(from: number) {
                return "\(sign)\(symbol)\(formatted)万"
            }
        }

        let number = NSDecimalNumber(decimal: absValue)
        if let formatted = shortIntegerFormatter.string(from: number) {
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
        let formatter = decimalCustomFormatter
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
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
            let f = symbolFormatter
            f.currencyCode = code
            return f.currencySymbol ?? code
        }
    }

    static func currencySymbol(for code: String) -> String {
        let formatter = symbolFormatter
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}
