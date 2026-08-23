import SwiftUI

// MARK: - Main Orchestrator View

struct MacCategoryChartView: View {
    let categories: [CategoryExpenseItem]
    let totalExpense: Decimal
    let centerTitle: String
    let isDrilledDown: Bool
    let isShowingTransactions: Bool
    let transactions: [Transaction]
    @Binding var categoryType: TransactionType
    let onCategoryTap: (UUID) -> Void
    let onCenterTap: () -> Void
    let onSelectTransaction: ((Transaction) -> Void)?

    // MARK: - Member Split Support

    var isMemberSplitOn: Binding<Bool>?
    var memberDonutCategories: [CategoryExpenseItem] = []
    var memberTotalExpense: Decimal = 0
    var memberSplits: [UUID: [CategoryMemberSplit]] = [:]
    var onToggleMemberSplit: (() -> Void)?

    @State private var barProgress: Double = 0
    @State private var pieProgress: Double = 0
    @State private var explodedIndex: Int? = nil
    @State private var hoveredIndex: Int? = nil

    private var memberSplitActive: Bool {
        isMemberSplitOn?.wrappedValue == true
    }

    /// L2: member mode + drilled into a category
    private var isL2MemberMode: Bool {
        memberSplitActive && isDrilledDown
    }

    /// L1: member mode at category overview
    private var isL1MemberMode: Bool {
        memberSplitActive && !isDrilledDown
    }

    // MARK: - Computed Donut Data

    /// L1 成员模式：饼图切换为成员占比；L2 保持分类饼图（成员拆分在下方列表中）
    private var donutCategories: [CategoryExpenseItem] {
        isL1MemberMode ? memberDonutCategories : categories
    }

    private var donutTotal: Decimal {
        isL1MemberMode ? memberTotalExpense : totalExpense
    }

    private var donutTitle: String {
        isL1MemberMode ? String(localized: "成员占比") : centerTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            if isShowingTransactions && !memberSplitActive {
                TransactionDetailList(
                    transactions: transactions,
                    centerTitle: centerTitle,
                    totalExpense: totalExpense,
                    onBack: onCenterTap,
                    onSelectTransaction: onSelectTransaction
                )
            } else if categories.isEmpty {
                emptyView
            } else {
                DonutChart(
                    categories: donutCategories,
                    totalExpense: donutTotal,
                    centerTitle: donutTitle,
                    isDrilledDown: isDrilledDown,
                    categoryType: $categoryType,
                    onCategoryTap: memberSplitActive ? { _ in } : onCategoryTap,
                    onCenterTap: { onCenterTap() },
                    pieProgress: $pieProgress,
                    explodedIndex: $explodedIndex,
                    hoveredIndex: $hoveredIndex
                )
                .glassCard(cornerRadius: 20)
                .overlay(alignment: .bottomTrailing) {
                    memberToggleButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 20)

                ScrollView {
                    CategoryBarList(
                        categories: isL1MemberMode ? memberDonutCategories : categories,
                        barProgress: barProgress,
                        hoveredIndex: $hoveredIndex,
                        explodedIndex: $explodedIndex,
                        onCategoryTap: memberSplitActive ? { _ in } : onCategoryTap,
                        memberSplits: isL2MemberMode ? memberSplits : [:]
                    )
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear { triggerAnimations() }
        .onChange(of: categories.map(\.id)) { _, _ in
            explodedIndex = nil
            triggerAnimations()
        }
        .onChange(of: memberSplitActive) { _, _ in
            explodedIndex = nil
            triggerAnimations()
        }
    }

    // MARK: - Member Toggle Button

    @ViewBuilder
    private var memberToggleButton: some View {
        if isMemberSplitOn != nil {
            Button {
                isMemberSplitOn?.wrappedValue.toggle()
                if isMemberSplitOn?.wrappedValue == true {
                    onToggleMemberSplit?()
                }
            } label: {
                Image(systemName: "person.2.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        memberSplitActive
                            ? Color.designAccentGreen
                            : Color.designOnSurfaceVariant
                    )
                    .padding(10)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    )
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    // MARK: - Animation Trigger

    private func triggerAnimations() {
        barProgress = 0
        pieProgress = 0
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { barProgress = 1 }
            withAnimation(.easeOut(duration: 0.9)) { pieProgress = 1 }
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无支出数据")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
