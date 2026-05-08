import Foundation

enum LendingDirection: String, Codable, CaseIterable {
    case lendOut = "借出"
    case borrowIn = "借入"
    case collect = "收款"
    case repay = "还款"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }

    var systemIcon: String {
        switch self {
        case .lendOut: "arrow.up.right"
        case .borrowIn: "arrow.down.left"
        case .collect: "arrow.down.left"
        case .repay: "arrow.up.right"
        }
    }

    var pendingLabel: String {
        switch self {
        case .lendOut: NSLocalizedString("待收款", comment: "")
        case .borrowIn: NSLocalizedString("待付款", comment: "")
        case .collect, .repay: ""
        }
    }
}
