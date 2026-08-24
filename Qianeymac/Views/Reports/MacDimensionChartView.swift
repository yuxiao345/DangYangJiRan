import SwiftUI

// MARK: - Mac Dimension Chart View (多维分析)

struct MacDimensionChartView: View {
    // L1: dimension overview
    let donutItems: [CategoryExpenseItem]       // Top N + "其他" for donut
    let allItems: [CategoryExpenseItem]          // Full list for CategoryBarList
    let totalExpense: Decimal
    let title: String

    // Dimension toggle (L1 only)
    @Binding var selectedDimension: DimensionType

    // Drill-down state
    let isDrilledDown: Bool
    let transactions: [Transaction]
    let drillDownTitle: String
    let drillDownTotal: Decimal
    let drillDownCategories: [CategoryExpenseItem]  // For project category level

    // Callbacks
    let onCategoryTap: (UUID) -> Void
    let onCenterTap: () -> Void
    let onDrillDownCategoryTap: (UUID) -> Void      // Project category tap

    @State private var barProgress: Double = 0
    @State private var pieProgress: Double = 0
    @State private var explodedIndex: Int? = nil
    @State private var hoveredIndex: Int? = nil
    @State private var categoryType: TransactionType = .expense

    private var isShowingTransactions: Bool {
        isDrilledDown && !transactions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if isShowingTransactions {
                TransactionDetailList(
                    transactions: transactions,
                    centerTitle: drillDownTitle,
                    totalExpense: drillDownTotal,
                    onBack: onCenterTap,
                    onSelectTransaction: nil
                )
            } else if isDrilledDown && !drillDownCategories.isEmpty {
                chartSection(
                    donutCategories: drillDownCategories,
                    barCategories: drillDownCategories,
                    centerTitle: drillDownTitle,
                    total: drillDownTotal,
                    isDrilledDown: true,
                    showTopBar: true,
                    onCategoryTap: onDrillDownCategoryTap
                )
            } else if allItems.isEmpty {
                emptyView
            } else {
                // L1: dimension overview with toggle inside card
                VStack(spacing: 0) {
                    dimensionToggle
                    DonutChart(
                        categories: donutItems,
                        totalExpense: totalExpense,
                        centerTitle: title,
                        isDrilledDown: false,
                        showTopBar: false,
                        categoryType: $categoryType,
                        onCategoryTap: onCategoryTap,
                        onCenterTap: {},
                        pieProgress: $pieProgress,
                        explodedIndex: $explodedIndex,
                        hoveredIndex: $hoveredIndex
                    )
                }
                .glassCard(cornerRadius: 20)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 20)

                ScrollView {
                    CategoryBarList(
                        categories: allItems,
                        barProgress: barProgress,
                        hoveredIndex: $hoveredIndex,
                        explodedIndex: $explodedIndex,
                        onCategoryTap: onCategoryTap
                    )
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear { triggerAnimations() }
        .onChange(of: allItems.map(\.id)) { _, _ in resetAndAnimate() }
        .onChange(of: drillDownCategories.map(\.id)) { _, _ in resetAndAnimate() }
    }

    // MARK: - Dimension Toggle (inside donut card, top-left)

    /// 位置与 DonutChart topBar 完全一致：HStack + Spacer 推左。
    private var dimensionToggle: some View {
        HStack {
            HStack(spacing: 0) {
                ForEach(DimensionType.allCases, id: \.self) { dim in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDimension = dim
                        }
                    } label: {
                        Text(dim.label)
                            .font(.designBodyMedium)
                            .foregroundStyle(
                                selectedDimension == dim
                                    ? Color.designOnSurface
                                    : Color.designOnSurfaceVariant.opacity(0.7)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .background(dimensionPillBackground(active: selectedDimension == dim))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background { Capsule().fill(Color.designGlassBg) }
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1) }
            .overlay { Capsule().stroke(Color.white.opacity(0.04), lineWidth: 1).padding(1) }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 17)
    }

    @ViewBuilder
    private func dimensionPillBackground(active: Bool) -> some View {
        if active {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1) }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    // MARK: - Chart Section

    private func chartSection(
        donutCategories: [CategoryExpenseItem],
        barCategories: [CategoryExpenseItem],
        centerTitle: String,
        total: Decimal,
        isDrilledDown: Bool,
        showTopBar: Bool,
        onCategoryTap: @escaping (UUID) -> Void
    ) -> some View {
        Group {
            DonutChart(
                categories: donutCategories,
                totalExpense: total,
                centerTitle: centerTitle,
                isDrilledDown: isDrilledDown,
                showTopBar: showTopBar,
                categoryType: $categoryType,
                onCategoryTap: onCategoryTap,
                onCenterTap: onCenterTap,
                pieProgress: $pieProgress,
                explodedIndex: $explodedIndex,
                hoveredIndex: $hoveredIndex
            )
            .glassCard(cornerRadius: 20)
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 20)

            ScrollView {
                CategoryBarList(
                    categories: barCategories,
                    barProgress: barProgress,
                    hoveredIndex: $hoveredIndex,
                    explodedIndex: $explodedIndex,
                    onCategoryTap: onCategoryTap
                )
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Animation

    private func triggerAnimations() {
        barProgress = 0
        pieProgress = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { barProgress = 1 }
            withAnimation(.easeOut(duration: 0.9)) { pieProgress = 1 }
        }
    }

    private func resetAndAnimate() {
        explodedIndex = nil
        triggerAnimations()
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
