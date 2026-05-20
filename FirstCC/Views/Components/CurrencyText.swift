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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = true
        formatter.currencySymbol = simpleCurrencySymbol

        let number = NSDecimalNumber(decimal: amount)
        guard var result = formatter.string(from: number) else {
            return "\(amount)"
        }

        if showSign, amount > 0 {
            result = "+" + result
        }

        return result
    }

    /// Use clean currency symbols without locale-specific country prefixes.
    /// zh-CN locale adds "US" prefix to "$" for USD — this strips it.
    private var simpleCurrencySymbol: String {
        switch currencyCode {
        case "USD", "AUD", "CAD", "SGD": return "$"
        case "CNY", "JPY": return "¥"
        case "EUR": return "€"
        case "GBP": return "£"
        case "HKD": return "HK$"
        case "TWD": return "NT$"
        default:
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currencyCode
            return f.currencySymbol ?? currencyCode
        }
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
