import Foundation
@preconcurrency import CoreData

/// 预算项导航目标：item + scope（本期 / 累计）+ 进度线金额实际使用的日期区间。
/// 用作 navigationDestination(item:) 的可识别值，避免为每个 scope 开独立 @State。
struct BudgetItemNavEntry: Identifiable, Hashable {
    /// 页面上两条进度线各自算金额时用的区间，成对出现
    struct ResolvedRanges: Hashable {
        let currentPeriod: ClosedRange<Date>
        let cumulative: ClosedRange<Date>
    }

    let item: BudgetItem
    let scope: BudgetScope

    /// 进度线金额所依据的区间。带月份导航的页面（iOS）必须传：那个页面的「本期」是所选自然月，
    /// 而不是预算项的真实当期，明细页若自行按 scope 推导就会列出与金额不符的交易。
    /// nil = 明细页按 scope 推导（Mac 行金额本就按预算项周期计算，两者天然一致）。
    var ranges: ResolvedRanges? = nil

    /// 明细页取数用的区间；nil 表示交给 service 按 scope 推导
    func dateRange(for scope: BudgetScope) -> ClosedRange<Date>? {
        switch scope {
        case .currentPeriod: ranges?.currentPeriod
        case .cumulative:    ranges?.cumulative
        }
    }

    var id: String { "\(item.id)-\(scope.rawValue)" }
}
