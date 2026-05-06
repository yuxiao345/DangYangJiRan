import Foundation

enum RecurringFrequency: String, Codable, CaseIterable {
    case daily = "每天"
    case weekly = "每周"
    case monthly = "每月"
    case yearly = "每年"
}
