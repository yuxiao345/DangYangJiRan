import SwiftUI

struct CurrencyText: View {
    let amount: Decimal
    let currencyCode: String
    var showSign: Bool = false
    var size: CGFloat = 17
    var foregroundColor: Color = .primary
    var fractionDigits: Int = 2

    var body: some View {
        Text(formatted)
            .font(.custom("JetBrainsMono-Medium", fixedSize: size))
            .foregroundStyle(foregroundColor)
    }

    private var formatted: String {
        let formatter = CurrencyFormatterCache.formatter(
            currencyCode: currencyCode,
            fractionDigits: fractionDigits
        )
        let number = NSDecimalNumber(decimal: amount)
        guard var result = formatter.string(from: number) else {
            return "\(amount)"
        }

        if showSign, amount > 0 {
            result = "+" + result
        }

        return result
    }
}

extension CurrencyText {
    init(amount: Decimal, currencyCode: String = "CNY") {
        self.amount = amount
        self.currencyCode = currencyCode
        self.showSign = false
        self.size = 17
        self.foregroundColor = amount >= 0 ? .primary : Color.red
    }
}

// MARK: - Formatter cache

private enum CurrencyFormatterCache {
    /// Cache one NumberFormatter per (currencyCode, fractionDigits) pair.
    /// CurrencyText is used ~85 times across the app; without this cache
    /// each body re-render allocates two NumberFormatter + NSDecimalNumber.
    private static let cache = NSCache<NSString, NumberFormatter>()

    static func formatter(currencyCode: String, fractionDigits: Int) -> NumberFormatter {
        let key = "\(currencyCode)-\(fractionDigits)" as NSString
        if let existing = cache.object(forKey: key) {
            return existing
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        f.usesGroupingSeparator = true
        f.currencySymbol = simpleCurrencySymbol(for: currencyCode)
        cache.setObject(f, forKey: key)
        return f
    }

    /// Use clean currency symbols without locale-specific country prefixes.
    /// zh-CN locale adds "US" prefix to "$" for USD — this strips it.
    static func simpleCurrencySymbol(for code: String) -> String {
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
}
