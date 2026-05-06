import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case income = "收入"
    case expense = "支出"
    case transfer = "转账"
    case lending = "借贷"
    case adjustment = "调整"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }

    var systemIcon: String {
        switch self {
        case .income: "arrow.down.circle"
        case .expense: "arrow.up.circle"
        case .transfer: "arrow.left.arrow.right.circle"
        case .lending: "arrow.triangle.swap"
        case .adjustment: "pencil.circle"
        }
    }
}
