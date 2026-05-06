import SwiftUI

struct CurrencyText: View {
    let amount: Decimal
    let currencyCode: String
    var showSign: Bool = false
    var font: Font = .body
    var foregroundColor: Color = .primary

    var body: some View {
        Text(formatted)
            .font(font.monospacedDigit())
            .foregroundStyle(foregroundColor)
    }

    private var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true

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
        self.font = .body
        self.foregroundColor = amount >= 0 ? .primary : Color.red
    }
}
