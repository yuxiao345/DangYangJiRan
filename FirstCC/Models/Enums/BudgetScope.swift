import Foundation

/// 预算项的时间范围维度。从预算项跳转明细页时使用，决定明细页过滤的日期区间。
enum BudgetScope: String, Hashable, Codable, CaseIterable {
    /// 本期：按 BudgetItem.period 算周/月/季/年的真实当期
    case currentPeriod
    /// 累计：账本起始日 → 今天
    case cumulative

    var displayName: String {
        switch self {
        case .currentPeriod: NSLocalizedString("本期", comment: "")
        case .cumulative:    NSLocalizedString("累计", comment: "")
        }
    }
}