import Foundation

enum LendingStatus: String, Codable {
    case active = "进行中"
    case settled = "已结清"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }
}
