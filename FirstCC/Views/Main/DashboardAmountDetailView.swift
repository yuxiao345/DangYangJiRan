import SwiftUI
@preconcurrency import CoreData

/// 总览「本月收入 / 本月支出」卡片的明细页（iOS）。
///
/// 交易集合由与卡片金额完全相同的入口算出（收入：`TransactionService.incomeTransactions`；
/// 支出：`BudgetService.expenseTransactions`），再通过 `presetTransactions` 下传给通用列表。
/// 列表自己不再查一遍——两套过滤规则会让「点进去的合计」与卡片数字对不上。
struct DashboardAmountDetailView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let entry: DashboardAmountNavEntry

    /// nil = 首次加载尚未完成。用可选值而不是空数组，避免首帧闪一下「暂无交易」。
    @State private var transactions: [Transaction]?

    var body: some View {
        VStack(spacing: 0) {
            Text(LocalizedStringKey(entry.kind.scopeNote))
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if let transactions {
                TransactionListView(
                    options: [.hideTypeFilter, .hideAddButton, .hideScreenBackground],
                    presetTransactions: transactions,
                    title: LocalizedStringKey(entry.kind.displayName)
                )
            }
        }
        // 背景由页面根节点统一画，列表自己那层已用 .hideScreenBackground 关掉
        .designScreen()
        .task(id: entry) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in reload() }
        // 明细只属于发起跳转的那个账本；账本一换就退出，否则重载会静默换成新账本的数据
        .onChange(of: appContainer.currentLedger?.id) { _, newID in
            if newID != entry.ledgerID { dismiss() }
        }
    }

    private func reload() {
        guard let ledger = appContainer.currentLedger, ledger.id == entry.ledgerID else {
            transactions = nil
            return
        }
        switch entry.kind {
        case .income:
            transactions = appContainer.transactionService.incomeTransactions(
                in: entry.incomeRange,
                for: ledger,
                context: modelContext
            )
        case .expense:
            transactions = appContainer.budgetService.expenseTransactions(
                in: entry.expenseRange,
                ledger: ledger,
                context: modelContext
            )
        }
    }
}
