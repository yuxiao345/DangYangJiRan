import SwiftUI
@preconcurrency import CoreData

/// 预算项明细页（Mac）：在 TransactionListContent 之上套一层 scope chip。
/// scope 切换时重算闭区间并下传 filterDateRange；TransactionListContent 自身不需要知道 BudgetScope。
struct BudgetItemTransactionListMacView: View {
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
            BudgetScopeChipsBar(currentScope: currentScope) { newScope in
                currentScope = newScope
            }
            if let range = currentRange {
                TransactionListContent(
                    selectedDate: .constant(nil),
                    filterCategory: item.category,
                    options: [.hideTypeFilter, .hideAddButton],
                    filterDateRange: range
                )
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

// MARK: - Chips (glass style)

private struct BudgetScopeChipsBar: View {
    let currentScope: BudgetScope
    let onSelect: (BudgetScope) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BudgetScope.allCases, id: \.self) { scope in
                chip(scope)
            }
            Spacer()
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color.designGlassBg)
        }
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func chip(_ scope: BudgetScope) -> some View {
        let isSelected = currentScope == scope
        return Button {
            onSelect(scope)
        } label: {
            Text(LocalizedStringKey(scope.displayName))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isSelected ? Color.designOnSurface : Color.designOnSurfaceVariant.opacity(0.7)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .background(.regularMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(scope.displayName)
    }
}