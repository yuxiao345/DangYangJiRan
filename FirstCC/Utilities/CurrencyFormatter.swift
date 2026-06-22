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
        currencyCode: String = "CNY",
        showSymbol: Bool = true
    ) -> String {
        let absValue = amount.absoluteValue
        let sign = amount.isNegative ? "-" : ""
        let symbol = showSymbol ? simpleCurrencySymbol(for: currencyCode.isEmpty ? "CNY" : currencyCode) : ""

        let number = NSDecimalNumber(decimal: absValue)
        if let compact = compactNumberString(from: number, sign: sign, symbol: symbol) {
            return compact
        }

        if let formatted = shortIntegerFormatter.string(from: number) {
            return "\(sign)\(symbol)\(formatted)"
        }
        return "\(sign)\(symbol)0"
    }

    /// Compact number formatting for axis labels and net amounts (no symbol, handles 万/k)
    static func formatCompactNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        let isChinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? true

        if value >= 10000 && isChinese {
            let wan = value / 10000
            return wan.formatted(.number.precision(.fractionLength(0...1))) + String(localized: "万")
        }
        if value >= 1000 {
            let k = value / 1000
            return k.formatted(.number.precision(.fractionLength(0...1))) + "k"
        }
        return value.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
    }

    /// Shared compact suffix logic: returns "X万" string if applicable, nil otherwise
    private static func compactNumberString(from number: NSDecimalNumber, sign: String, symbol: String) -> String? {
        let isChinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? true
        let absDecimal = number.decimalValue.absoluteValue

        if absDecimal >= 10000 && isChinese {
            let wan = absDecimal / 10000
            if let formatted = shortWanFormatter.string(from: NSDecimalNumber(decimal: wan)) {
                return "\(sign)\(symbol)\(formatted)\(String(localized: "万"))"
            }
        }
        return nil
    }

    /// Adaptive: uses formatDecimal for amounts under 10k (precision), formatShort for 10k+ (compact).
    static func formatAdaptive(amount: Decimal, currencyCode: String = "") -> String {
        if amount.absoluteValue >= 10000 {
            return formatShort(amount: amount, currencyCode: currencyCode)
        }
        return formatDecimal(amount: amount, currencyCode: currencyCode)
    }

    static func formatDecimal(
        amount: Decimal,
        currencyCode: String? = nil,
        fractionDigits: Int = 2,
        showAbs: Bool = false
    ) -> String {
        let value = showAbs ? amount.absoluteValue : amount
        let formatter = decimalCustomFormatter
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let numberStr = formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
        guard let code = currencyCode else { return numberStr }
        let symbol = simpleCurrencySymbol(for: code.isEmpty ? "CNY" : code)
        return "\(symbol)\(numberStr)"
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
