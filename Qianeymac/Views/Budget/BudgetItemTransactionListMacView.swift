import SwiftUI
@preconcurrency import CoreData

/// 预算项明细页（Mac）：在 TransactionListContent 之上套一层 scope 切换器。
/// 交易集合由 BudgetService 用与金额统计完全相同的规则与日期区间算好后直接下传，
/// TransactionListContent 既不需要知道 BudgetScope，也不会再自行过滤一遍。
struct BudgetItemTransactionListMacView: View {
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
            scopeToggle
            if let transactions {
                // 只下传 preset：分类与日期口径已由 service 按金额同一条路径算好，列表不再自行过滤
                TransactionListContent(
                    selectedDate: .constant(nil),
                    options: [.hideTypeFilter, .hideAddButton],
                    presetTransactions: transactions
                )
            }
        }
        .task(id: currentScope) { reload() }
        // entry 变化也要重载：id 只含 item+scope，若 SwiftUI 复用了 destination 视图，
        // 只盯 currentScope 会漏掉区间不同的新 entry
        .onChange(of: entry) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in reload() }
    }

    /// 与报表页维度切换器同款（GlassPillToggle），置于内容顶部左对齐
    private var scopeToggle: some View {
        HStack {
            GlassPillToggle(options: BudgetScope.allCases, selection: $currentScope) { scope in
                scope.displayName
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 17)
        .padding(.bottom, 4)
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
