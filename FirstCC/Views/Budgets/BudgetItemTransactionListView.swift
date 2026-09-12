import SwiftUI
@preconcurrency import CoreData

/// 预算项明细页：在通用 TransactionListView 之上套一层 scope chip。
/// scope 切换时重算闭区间并下传 filterDateRange；TransactionListView 自身不需要知道 BudgetScope。
struct BudgetItemTransactionListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    let item: BudgetItem
    let initialScope: BudgetScope

    @State private var currentScope: BudgetScope
    @State private var currentRange: ClosedRange<Date>?

    init(item: BudgetItem, initialScope: BudgetScope) {
        self.item = item
        self.initialScope = initialScope
        self._currentScope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let range = currentRange {
                TransactionListView(
                    filterCategory: item.category,
                    options: [.hideTypeFilter, .hideAddButton],
                    filterDateRange: range
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BudgetScopeChipsBar(currentScope: currentScope) { newScope in
                currentScope = newScope
            }
        }
        .task(id: currentScope) {
            currentRange = scopeRange(currentScope)
        }
        .onChange(of: currentScope) { _, new in
            currentRange = scopeRange(new)
        }
    }

    private func scopeRange(_ scope: BudgetScope) -> ClosedRange<Date> {
        let service = appContainer.budgetService
        return scope == .currentPeriod
            ? service.currentPeriodRange(for: item, context: modelContext)
            : service.cumulativeRange(for: item, context: modelContext)
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