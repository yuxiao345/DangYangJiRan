import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case income = "收入"
    case expense = "支出"
    case transfer = "转账"
    case adjustment = "调整"
}
