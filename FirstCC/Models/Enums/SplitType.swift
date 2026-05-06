import Foundation

enum SplitType: String, Codable, CaseIterable {
    case equal = "均分"
    case percentage = "按比例"
    case fixed = "固定金额"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }
}
