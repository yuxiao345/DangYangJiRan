import Foundation

enum AccountType: String, Codable, CaseIterable {
    case cash = "现金"
    case debitCard = "借记卡"
    case creditCard = "信用卡"
    case eWallet = "电子钱包"
    case housingFund = "公积金"
    case investment = "投资"
    case loan = "贷款"
    case insurance = "保险"
    case other = "自定义"

    var systemIcon: String {
        switch self {
        case .cash: "banknote"
        case .debitCard: "creditcard.and.123"
        case .creditCard: "creditcard"
        case .eWallet: "wallet.pass"
        case .housingFund: "house"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "building.columns"
        case .insurance: "shield.checkered"
        case .other: "square.grid.2x2"
        }
    }
}
