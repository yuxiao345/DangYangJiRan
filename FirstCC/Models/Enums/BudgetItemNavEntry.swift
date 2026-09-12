import Foundation
@preconcurrency import CoreData

/// 预算项导航目标：item + scope（本期 / 累计）。
/// 用作 navigationDestination(item:) 的可识别值，避免为每个 scope 开独立 @State。
struct BudgetItemNavEntry: Identifiable, Hashable {
    let item: BudgetItem
    let scope: BudgetScope

    var id: String { "\(item.id)-\(scope.rawValue)" }
}