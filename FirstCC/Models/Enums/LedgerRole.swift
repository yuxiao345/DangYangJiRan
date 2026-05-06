import Foundation

enum LedgerRole: String, Codable {
    case owner = "拥有者"
    case admin = "管理员"
    case member = "成员"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }
}
