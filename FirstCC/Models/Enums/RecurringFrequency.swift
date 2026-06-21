import Foundation

enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "每天"
    case weekly = "每周"
    case monthly = "每月"
    case yearly = "每年"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }

    var unitName: String {
        switch self {
        case .daily: return String(localized: "天")
        case .weekly: return String(localized: "周")
        case .monthly: return String(localized: "月")
        case .yearly: return String(localized: "年")
        }
    }
}
