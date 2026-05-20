import Foundation

struct CurrencyServiceImpl: CurrencyServiceProtocol {

    let supportedCurrencies: [String] = [
        "CNY", "USD", "EUR", "JPY", "GBP", "HKD", "AUD", "CAD",
        "KRW", "TWD", "SGD", "CHF", "NZD", "THB", "MYR", "INR",
    ]

    func format(amount: Decimal, currencyCode: String, showSign: Bool) -> String {
        CurrencyFormatter.format(amount: amount, currencyCode: currencyCode, showSign: showSign)
    }

    func symbol(for currencyCode: String) -> String {
        CurrencyFormatter.currencySymbol(for: currencyCode)
    }

    func convert(
        amount: Decimal,
        from sourceCurrency: String,
        to targetCurrency: String
    ) async throws -> Decimal? {
        guard sourceCurrency != targetCurrency else { return amount }

        let url = URL(string: "https://api.frankfurter.app/latest?from=\(sourceCurrency)&to=\(targetCurrency)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct Response: Decodable {
            let rates: [String: Decimal]
        }
        let decoder = JSONDecoder()
        let response = try decoder.decode(Response.self, from: data)
        guard let rate = response.rates[targetCurrency] else { return nil }
        return amount * rate
    }

    func currencyName(_ code: String) -> String {
        switch code {
        case "CNY": return "人民币"
        case "USD": return "美元"
        case "EUR": return "欧元"
        case "JPY": return "日元"
        case "GBP": return "英镑"
        case "HKD": return "港币"
        case "AUD": return "澳元"
        case "CAD": return "加元"
        case "KRW": return "韩元"
        case "TWD": return "新台币"
        case "SGD": return "新加坡元"
        case "CHF": return "瑞士法郎"
        case "NZD": return "新西兰元"
        case "THB": return "泰铢"
        case "MYR": return "马币"
        case "INR": return "印度卢比"
        default: return code
        }
    }
}
