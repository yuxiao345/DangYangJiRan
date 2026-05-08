import Foundation

enum LendingStatus: String, Codable, CaseIterable {
    case none = "无"
    case pending = "待结算"
    case settled = "已结清"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }
}
