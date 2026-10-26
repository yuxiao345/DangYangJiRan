import Foundation

/// 总览「本月收入 / 本月支出」卡片的跳转目标。
///
/// 同时收拢这两张卡的取数区间：区间必须由卡片渲染时所在的自然月推导，不能交给明细页
/// 现取 `Date.now`——跨月零点前后点开时，明细页若取到新月份，就会和卡片上的金额对不上。
struct DashboardAmountNavEntry: Hashable {
    enum Kind: Hashable {
        case income
        case expense

        /// 卡片标题，同时用作明细页标题
        var displayName: String {
            switch self {
            case .income: NSLocalizedString("本月收入", comment: "")
            case .expense: NSLocalizedString("本月支出", comment: "")
            }
        }

        /// 口径说明：卡片排除了报销相关交易，明细页必须写清楚，否则用户会以为漏记了。
        var scopeNote: String {
            switch self {
            case .income: NSLocalizedString("与总览口径一致：不含报销结算收入", comment: "")
            case .expense: NSLocalizedString("与总览口径一致：不含可报销支出", comment: "")
            }
        }
    }

    let kind: Kind
    /// 归零到月首 00:00，与 `DashboardViewModel.load` 的月度口径一致
    let monthStart: Date
    /// 发起跳转时所在的账本。明细页只认这个账本：切换账本后旧页面必须退出，
    /// 不能让「新账本 + 旧月份」的数据静默顶上来。
    let ledgerID: UUID

    /// 收入统计区间：月首（含）..< 下月首（不含）。
    /// 与 `DashboardViewModel` 拉取本月交易时用的 `monthStart..<monthEnd` 完全同源。
    static func rangeForIncome(monthStart: Date) -> Range<Date> {
        let cal = Calendar.current
        let end = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        return monthStart..<end
    }

    /// 支出统计区间：月首日界...月末日界（月末取到最后一秒）。
    /// 与 BudgetService 其它支出统计的端点一致。
    static func rangeForExpense(monthStart: Date) -> ClosedRange<Date> {
        monthStart.startOfDay...monthStart.endOfMonth
    }

    var incomeRange: Range<Date> { Self.rangeForIncome(monthStart: monthStart) }
    var expenseRange: ClosedRange<Date> { Self.rangeForExpense(monthStart: monthStart) }
}
