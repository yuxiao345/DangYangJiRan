import Foundation

enum BudgetPeriod: String, Codable, CaseIterable {
    case weekly = "每周"
    case monthly = "每月"
    case yearly = "每年"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }
}
