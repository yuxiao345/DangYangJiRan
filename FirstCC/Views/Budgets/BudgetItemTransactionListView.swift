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
            if let transactions {
                TransactionListView(
                    filterCategory: item.category,
                    options: [.hideTypeFilter, .hideAddButton],
                    presetTransactions: transactions
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BudgetScopeChipsBar(currentScope: currentScope) { newScope in
                currentScope = newScope
            }
        }
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

// MARK: - Chips

private struct BudgetScopeChipsBar: View {
    let currentScope: BudgetScope
    let onSelect: (BudgetScope) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BudgetScope.allCases, id: \.self) { scope in
                chip(scope)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func chip(_ scope: BudgetScope) -> some View {
        let isSelected = currentScope == scope
        return Button {
            onSelect(scope)
        } label: {
            Text(LocalizedStringKey(scope.displayName))
                .font(.designBodySmall)
                .foregroundStyle(isSelected ? .white : Color.designOnSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.designPrimaryContainer : Color.designOnSurfaceVariant.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(scope.displayName)
    }
}
