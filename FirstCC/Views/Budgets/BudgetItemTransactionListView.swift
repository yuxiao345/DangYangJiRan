import SwiftUI
@preconcurrency import CoreData

/// 预算项明细页：在通用 TransactionListView 之上套一层 scope 切换器。
/// 交易集合由 BudgetService 用与金额统计完全相同的规则与日期区间算好后直接下传，
/// TransactionListView 既不需要知道 BudgetScope，也不会再自行过滤一遍。
struct BudgetItemTransactionListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let entry: BudgetItemNavEntry

    @State private var currentScope: BudgetScope
    @State private var transactions: [Transaction]?

    init(entry: BudgetItemNavEntry) {
        self.entry = entry
        // entry.scope 只用于决定初始选中项，之后由 currentScope 独立持有
        self._currentScope = State(initialValue: entry.scope)
    }

    private var item: BudgetItem { entry.item }

    var body: some View {
        VStack(spacing: 0) {
            // 与报表页同一个控件（DesignSegmentedBar）
            DesignSegmentedBar(options: BudgetScope.allCases, selection: $currentScope) { scope in
                scope.displayName
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // 给卡片阴影留出呼吸空间；贴着下面的明细层时下方阴影会被盖掉
            .padding(.bottom, 12)

            if let transactions {
                TransactionListView(
                    filterCategory: item.category,
                    options: [.hideTypeFilter, .hideAddButton, .hideScreenBackground],
                    presetTransactions: transactions
                )
            }
        }
        // 背景由页面根节点统一画。列表自己那层 `.ignoresSafeArea()` 背景会压到分段条上，
        // 让「本期/累计」看得见却点不动
        .designScreen()
        .task(id: currentScope) { reload() }
        // entry 变化也要重载：id 只含 item+scope，换月份后同一 id 的 entry 区间不同，
        // 若 SwiftUI 复用了 destination 视图，只有 currentScope 变化才刷新会显示上一个月的明细
        .onChange(of: entry) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in reload() }
    }

    private func reload() {
        transactions = appContainer.budgetService.expenseTransactions(
            for: item,
            scope: currentScope,
            in: entry.dateRange(for: currentScope),
            context: modelContext
        )
    }
}
