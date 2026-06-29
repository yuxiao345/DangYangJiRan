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

    @State private var barProgress: Double = 0
    @State private var pieProgress: Double = 0
    @State private var explodedIndex: Int? = nil
    @State private var hoveredIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            if isShowingTransactions {
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
                    categories: categories,
                    totalExpense: totalExpense,
                    centerTitle: centerTitle,
                    isDrilledDown: isDrilledDown,
                    categoryType: $categoryType,
                    onCategoryTap: onCategoryTap,
                    onCenterTap: onCenterTap,
                    pieProgress: $pieProgress,
                    explodedIndex: $explodedIndex,
                    hoveredIndex: $hoveredIndex
                )
                ScrollView {
                    CategoryBarList(
                        categories: categories,
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
        .onChange(of: categories.map(\.id)) { _, _ in
            explodedIndex = nil
            triggerAnimations()
        }
    }

    // MARK: - Animation Trigger

    private func triggerAnimations() {
        barProgress = 0
        pieProgress = 0
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
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

// MARK: - Transaction Detail List

private struct TransactionDetailList: View {
    let transactions: [Transaction]
    let centerTitle: String
    let totalExpense: Decimal
    let onBack: () -> Void
    let onSelectTransaction: ((Transaction) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DesignGlassCircleButton())
                Text(centerTitle)
                    .font(.designBodyMedium)
                    .foregroundStyle(Color.designOnSurface)
                    .padding(.leading, 8)
                Spacer()
                CurrencyText(amount: totalExpense, currencyCode: "", size: 18, foregroundColor: Color.designOnSurface)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 24)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(transactions.sorted(by: { $0.date > $1.date }), id: \.id) { tx in
                        Button {
                            onSelectTransaction?(tx)
                        } label: {
                            TransactionRowView(transaction: tx)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}
