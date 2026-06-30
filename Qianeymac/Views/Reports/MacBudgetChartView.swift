import SwiftUI

struct MacBudgetChartView: View {
    let items: [BudgetItemData]
    let books: [BudgetBook]
    @Binding var selectedBookID: UUID?
    @Binding var dimension: BudgetViewDimension

    private var groupByPeriod: Bool { dimension == .overall }

    var body: some View {
        VStack(spacing: 0) {
            if books.isEmpty {
                emptyView
            } else {
                bookPicker
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                if items.isEmpty {
                    emptyBudgetView
                } else {
                    summaryCard
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                    ScrollView {
                        if groupByPeriod {
                            groupedItemList
                        } else {
                            flatItemList
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Book Picker

    private var bookPicker: some View {
        HStack {
            Picker(String(localized: "预算计划"), selection: $selectedBookID) {
                ForEach(books, id: \.id) { book in
                    Text(book.name).tag(Optional(book.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("暂无预算数据")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyBudgetView: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
            Text("该预算计划无预算项")
                .font(.designBodyMedium)
                .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Computed

    private var totals: (budget: Decimal, spent: Decimal) {
        items.reduce(into: (Decimal(0), Decimal(0))) { acc, item in
            acc.0 += item.budgetAmount
            acc.1 += item.spentAmount
        }
    }
    private var totalRemaining: Decimal { totals.budget - totals.spent }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 16) {
            summaryCell(label: String(localized: "总预算"), amount: totals.budget, color: Color.designPrimaryFixedDim)
            summaryCell(label: String(localized: "已花费"), amount: totals.spent, color: Color.designAccentRed)
            summaryCell(label: String(localized: "剩余"), amount: totalRemaining, color: totalRemaining >= 0 ? .blue : Color.designAccentRed)
        }
    }

    private func summaryCell(label: String, amount: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.designBodyCaption)
                .foregroundStyle(Color.designOnSurfaceVariant)
            CurrencyText(amount: amount, currencyCode: "", showSign: false, size: 18, foregroundColor: color, fractionDigits: 0)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Item Lists

    /// 整体模式：按周期分组（周/月/季/年）
    private var groupedItemList: some View {
        let grouped = Dictionary(grouping: items) { $0.period }
        let order: [BudgetPeriod] = BudgetPeriod.allCases.sorted(by: >)

        return VStack(spacing: 12) {
            ForEach(order, id: \.self) { period in
                if let sectionItems = grouped[period], !sectionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(period)
                        ForEach(sectionItems) { item in
                            budgetRow(item)
                        }
                    }
                }
            }
        }
    }

    /// 非整体模式：平铺列表
    private var flatItemList: some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                budgetRow(item)
            }
        }
    }

    private func sectionHeader(_ period: BudgetPeriod) -> some View {
        Text(period.displayName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
            .padding(.leading, 4)
    }

    // MARK: - Budget Row

    private func budgetRow(_ item: BudgetItemData) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: item.colorHex) ?? .gray)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurface)
                    if item.isCumulative {
                        Text("累计 (\(item.period.displayName))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    CurrencyText(amount: item.spentAmount, currencyCode: "", size: 14, foregroundColor: item.isOverBudget ? Color.designAccentRed : Color.designOnSurface)
                        .fontWeight(.medium)
                    HStack(spacing: 2) {
                        if item.isOverBudget {
                            Text("超支").font(.system(size: 9)).foregroundStyle(Color.designAccentRed)
                        }
                        Text(String(format: "%.0f%%", item.percentage * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(item.isOverBudget ? Color.designAccentRed : Color.designOnSurfaceVariant)
                    }
                }

                HStack(spacing: 2) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8))
                    CurrencyText(amount: item.budgetAmount, currencyCode: "", size: 11, foregroundColor: Color.designOnSurfaceVariant.opacity(0.7), fractionDigits: 0)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.designOnSurfaceVariant.opacity(0.1))
                        .frame(height: 8)
                    Capsule()
                        .fill(item.isOverBudget ? Color.designAccentRed : (Color(hex: item.colorHex) ?? .gray))
                        .frame(width: max(4, min(geo.size.width, geo.size.width * item.percentage)), height: 8)
                        .overlay(alignment: .top) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 3)
                                .padding(.horizontal, 2)
                        }
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 10)
    }
}
