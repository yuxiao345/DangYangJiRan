import Foundation

enum SettlementStatus: String, Codable {
    case unsettled = "未结算"
    case partial = "部分结算"
    case settled = "已结算"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }
}
