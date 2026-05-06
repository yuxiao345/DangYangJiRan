import Foundation

enum LedgerType: String, Codable, CaseIterable {
    case personal = "个人"
    case family = "家庭"
    case travel = "旅行"
    case business = "生意"
    case custom = "自定义"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }

    var systemIcon: String {
        switch self {
        case .personal: "person"
        case .family: "house"
        case .travel: "airplane"
        case .business: "briefcase"
        case .custom: "square.grid.2x2"
        }
    }
}
