import Foundation

enum BudgetPeriod: String, Codable, CaseIterable, Comparable {
    case weekly = "每周"
    case monthly = "每月"
    case quarterly = "每季"
    case yearly = "每年"

    var displayName: String { NSLocalizedString(rawValue, comment: "") }

    private var rank: Int {
        switch self {
        case .weekly: 0
        case .monthly: 1
        case .quarterly: 2
        case .yearly: 3
        }
    }

    static func < (lhs: BudgetPeriod, rhs: BudgetPeriod) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Period Normalization

extension Decimal {
    /// 将当前金额从 `source` 周期归一化到 `target` 周期。
    /// 例如：每周 ¥200 → 每月 = 200 × 52 / 12 ≈ ¥867
    func normalized(from source: BudgetPeriod, to target: BudgetPeriod) -> Decimal {
        guard source != target else { return self }
        // 先归一化到月，再从月转换到目标周期
        let monthly: Decimal = switch source {
        case .weekly:    self * 52 / 12
        case .monthly:   self
        case .quarterly: self / 3
        case .yearly:    self / 12
        }
        return switch target {
        case .weekly:    monthly * 12 / 52
        case .monthly:   monthly
        case .quarterly: monthly * 3
        case .yearly:    monthly * 12
        }
    }

    /// 归一化到月口径（便捷方法）
    func normalizedToMonthly(period: BudgetPeriod) -> Decimal {
        normalized(from: period, to: .monthly)
    }
}
