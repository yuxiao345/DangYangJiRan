import SwiftUI
import Charts
@preconcurrency import CoreData

struct DashboardContentColumn: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    var navigationPath: Binding<NavigationPath>
    @State private var viewModel = DashboardViewModel(
        accountService: AccountServiceImpl(), transactionService: TransactionServiceImpl()
    )
    @State private var showBudgetDetail = false
    @State private var isBudgetHovered = false
    @State private var showNetWorth = true
    @State private var animIncomeFrac: Double = 0
    @State private var animExpenseFrac: Double = 0
    @State private var animBalanceFrac: Double = 0
    @State private var animBudgetPercent: Double = 0

    // MARK: - Category Card State
    @State private var categoryPieProgress: Double = 0
    @State private var categoryExplodedIndex: Int? = 0
    @State private var categoryHoveredIndex: Int?
    @State private var selectedTransaction: Transaction?

    // MARK: - Allocation Drill State
    @State private var allocationDrilled: AccountAllocationItem.DrillKey?

    // MARK: - Layout

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                netWorthCard
                allocationCard
                incomeExpenseRow
                if viewModel.hasBudget {
                    HStack(alignment: .top, spacing: 12) {
                        // Left: budget + burn rate + category overview
                        VStack(spacing: 12) {
                            budgetSummaryCard
                            burnRateCard
                            categoryOverviewCard
                        }
                        .frame(maxWidth: .infinity)
                        // Right: recent transactions, independently scrollable
                        recentTransactionsCard
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    emptyBudgetCard
                    categoryOverviewCard
                        .frame(maxWidth: 360)
                }
            }
            .padding(24)
        }
        .designScreen()
        .onAppear { loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in loadAll() }
        .onChange(of: appContainer.currentLedger?.id) { _, _ in loadAll() }
        .sheet(isPresented: $showBudgetDetail) {
            if let book = viewModel.activeBudgetBook {
                BudgetBookDetailMacView(book: book)
            } else if let ledger = appContainer.currentLedger {
                BudgetBookListView(ledger: ledger)
            }
        }
        .sheet(item: $selectedTransaction) { t in
            MacAddTransactionSheet(editing: t, displayMode: true)
        }
    }

    private func loadAll() {
        guard let ledger = appContainer.currentLedger else { return }
        let vm = DashboardViewModel(
            accountService: appContainer.accountService,
            transactionService: appContainer.transactionService,
            ledger: ledger
        )
        vm.load(context: modelContext, budgetService: appContainer.budgetService)
        vm.loadBudget(context: modelContext, budgetService: appContainer.budgetService)
        vm.loadBudgetBurnRate(context: modelContext, budgetService: appContainer.budgetService)
        vm.loadCategoryOverview(
            ledger: ledger,
            transactionService: appContainer.transactionService,
            categoryService: appContainer.categoryService,
            context: modelContext
        )
        viewModel.copyFrom(vm)

        let maxRef = max(abs(viewModel.monthlyIncome), abs(viewModel.monthlyExpense))
        let anim = Animation.spring(response: 0.8, dampingFraction: 0.65)
        withAnimation(anim) {
            animIncomeFrac = maxRef > 0 ? Double(truncating: (abs(viewModel.monthlyIncome) / maxRef) as NSNumber) : 0
            animExpenseFrac = maxRef > 0 ? Double(truncating: (abs(viewModel.monthlyExpense) / maxRef) as NSNumber) : 0
            animBalanceFrac = maxRef > 0 ? Double(truncating: (abs(viewModel.monthlyIncome + viewModel.monthlyExpense) / maxRef) as NSNumber) : 0
            let limit = viewModel.budgetLimit
            animBudgetPercent = limit > 0 ? Double(truncating: (viewModel.budgetSpent / limit) as NSNumber) : 0
        }

        // Animate category pie
        categoryPieProgress = 0
        categoryExplodedIndex = 0
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.9)) { categoryPieProgress = 1 }
        }
    }

    private var currencyCode: String {
        appContainer.currentLedger?.defaultCurrencyCode ?? "CNY"
    }

    private func navigate(to report: ReportType) {
        navigationPath.wrappedValue.append(report)
    }

    // MARK: - 净资产

    private var netWorthCard: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("净资产")
                        .font(.designBodyMedium.weight(.bold))
                        .foregroundStyle(Color.designOnSurfaceVariant)
                        .tracking(0.4)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(CurrencyFormatter.currencySymbol(for: currencyCode))
                            .font(.custom("JetBrainsMono-Medium", fixedSize: 24))
                            .foregroundStyle(Color.designPrimaryFixedDim)
                        Group {
                            if showNetWorth {
                                Text(CurrencyFormatter.formatDecimal(amount: viewModel.totalBalance, fractionDigits: 2))
                                    .font(.designDisplayMobile)
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    ForEach(0..<5, id: \.self) { _ in
                                        CircleDot()
                                    }
                                }
                            }
                        }
                        .foregroundStyle(Color.designOnSurface)
                        .tracking(-0.6)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showNetWorth.toggle() }
                    } label: {
                        Image(systemName: showNetWorth ? "eye" : "eye.slash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
            }
            if let change = viewModel.balanceChange, let pct = viewModel.balanceChangePercent {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(change >= 0 ? "+" : "")\(CurrencyFormatter.formatDecimal(amount: change, fractionDigits: 2)) (\(String(format: "%.1f", Double(truncating: pct as NSNumber)))%)")
                        .font(.designMonoData)
                    Text("较上月")
                        .font(.designBodyCaption)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                .foregroundStyle(change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill((change >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed).opacity(0.12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { navigate(to: .assets) }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.designPrimaryFixedDim.opacity(0.15))
                .frame(width: 100, height: 100)
                .blur(radius: 30)
                .offset(x: 20, y: -20)
        }
    }

    // MARK: - 收入/支出/结余

    private var incomeExpenseRow: some View {
        let balance = viewModel.monthlyIncome + viewModel.monthlyExpense
        return HStack(spacing: 12) {
            metricCell(label: "本月收入", amount: viewModel.monthlyIncome, frac: animIncomeFrac, color: Color.designPrimaryFixedDim)
            metricCell(label: "本月支出", amount: abs(viewModel.monthlyExpense), frac: animExpenseFrac, color: Color.designAccentRed)
            metricCell(label: "本月结余", amount: balance, frac: animBalanceFrac, color: balance >= 0 ? Color.designPrimaryFixedDim : Color.designAccentRed)
        }
    }

    private func metricCell(label: String, amount: Decimal, frac: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.designBodyMedium.weight(.semibold))
                .foregroundStyle(Color.designOnSurfaceVariant)
                .tracking(0.4)
            CurrencyText(amount: amount, currencyCode: currencyCode, showSign: false, size: 22, foregroundColor: color, fractionDigits: 0)
            PixelProgressBar(progress: frac, tint: color.opacity(0.6), totalBlocks: 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 预算

    private var budgetSummaryCard: some View {
        let spent = viewModel.budgetSpent
        let limit = viewModel.budgetLimit
        let percent = limit > 0 ? Double(truncating: (spent / limit) as NSNumber) : 0
        let remaining = limit - spent
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本月预算")
                    .font(.designBodyMedium.weight(.bold))
                    .foregroundStyle(isBudgetHovered ? Color.designAccentGreen : Color.designOnSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.designBodyCaption)
                    .foregroundStyle(isBudgetHovered ? Color.designAccentGreen : Color.secondary)
                    .offset(x: isBudgetHovered ? 2 : 0)
            }
            PixelProgressBar(progress: min(animBudgetPercent, 1), tint: Color.progressTint(for: animBudgetPercent), totalBlocks: 20)
            HStack {
                Text("已支出 \(CurrencyFormatter.formatDecimal(amount: spent, fractionDigits: 0, showAbs: true))")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                Spacer()
                Text("预算 \(CurrencyFormatter.formatDecimal(amount: limit, fractionDigits: 0, showAbs: true))")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { isBudgetHovered = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { showBudgetDetail = true }
    }

    private var emptyBudgetCard: some View {
        VStack(spacing: 8) {
            Text("本月预算")
                .font(.designBodyMedium.weight(.bold))
                .foregroundStyle(isBudgetHovered ? Color.designAccentGreen : Color.designOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Image(systemName: "plus.circle")
                    .font(.designHeadlineMedium)
                Text("设置预算，掌控每月开支")
                    .font(.designBodyMedium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.designBodyCaption)
            }
            .foregroundStyle(Color.designOnSurfaceVariant)
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { isBudgetHovered = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture { showBudgetDetail = true }
    }

    // MARK: - 资产配置瀑布

    private var allocationCard: some View {
        let totalAssets = viewModel.allocationItems.filter { !$0.isLiability }.reduce(Decimal.zero) { $0 + $1.balance }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if allocationDrilled == nil {
                    Text("资产配置")
                        .font(.designBodyMedium.weight(.bold))
                        .foregroundStyle(Color.designOnSurface)
                        .contentShape(Rectangle())
                        .onTapGesture { navigate(to: .allocation) }
                } else {
                    Text("资产配置")
                        .font(.designBodyMedium.weight(.bold))
                        .foregroundStyle(Color.designOnSurface)
                }

                if let key = allocationDrilled {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { allocationDrilled = nil }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                            Text(String(localized: "全部"))
                            Text("·")
                            Image(systemName: key.iconName).font(.system(size: 10))
                            Text(key.displayName)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    .buttonStyle(DesignGlassTextButton())
                } else {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                }
            }

            if viewModel.allocationItems.isEmpty {
                Text("暂无账户数据")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                waterfallChart(totalAssets: totalAssets)
                    .overlay(alignment: .topTrailing) {
                        if let key = allocationDrilled {
                            Text(key.displayName)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.designOnSurfaceVariant)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.regularMaterial))
                                .padding(6)
                        }
                    }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private func waterfallChart(totalAssets: Decimal) -> some View {
        // 共享聚合：L1 类型聚合；L2 沿用 drilled 键
        let items = viewModel.allocationItems
        let nodes: [AccountAllocationItem.AllocationNode]
        if let key = allocationDrilled {
            nodes = AllocationAggregator.drillDown(items, to: key)
        } else {
            nodes = AllocationAggregator.aggregate(items)
        }
        let assetNodes = nodes.filter { !$0.isLiability }
        let liabNodes = nodes.filter { $0.isLiability }
        let isL2 = allocationDrilled != nil

        // Pre-compute waterfall segments with stable index-based IDs
        struct Segment: Identifiable {
            let id: Int
            let axisKey: String   // 唯一 X 分类键（= node.id），避免同名类型两侧挤到同一 X 位置
            let label: String     // X 轴显示名
            let yStart: Decimal
            let yEnd: Decimal
            let isSummary: Bool
            let isAsset: Bool
        }

        var segments: [Segment] = []
        var idx = 0
        var running = Decimal.zero
        for item in assetNodes {
            let end = running + item.balance
            segments.append(Segment(id: idx, axisKey: item.id, label: item.name, yStart: running, yEnd: end, isSummary: false, isAsset: true))
            idx += 1; running = end
        }
        if !isL2 {
            segments.append(Segment(id: idx, axisKey: "summary|assets", label: String(localized: "总资产"), yStart: 0, yEnd: totalAssets, isSummary: true, isAsset: true))
            idx += 1; running = totalAssets
        }
        for item in liabNodes {
            let absBal = abs(item.balance)
            let end = running - absBal
            segments.append(Segment(id: idx, axisKey: item.id, label: item.name, yStart: running, yEnd: end, isSummary: false, isAsset: false))
            idx += 1; running = end
        }
        if !isL2 {
            segments.append(Segment(id: idx, axisKey: "summary|net", label: String(localized: "净资产"), yStart: 0, yEnd: viewModel.totalBalance, isSummary: true, isAsset: viewModel.totalBalance >= 0))
        }

        // Connector: dashed line tracing running total across non-summary bars
        struct ConnectorPoint: Identifiable {
            let id: Int
            let axisKey: String
            let value: Decimal
        }
        let connectorData = segments.filter { !$0.isSummary }.map { ConnectorPoint(id: $0.id, axisKey: $0.axisKey, value: $0.yEnd) }

        // axisKey → 显示名映射，供 X 轴标签渲染
        let labelMap = Dictionary(segments.map { ($0.axisKey, $0.label) }, uniquingKeysWith: { first, _ in first })

        return Chart {
            ForEach(segments) { seg in
                BarMark(
                    x: .value("", seg.axisKey),
                    yStart: .value("Start", seg.yStart),
                    yEnd: .value("End", seg.yEnd),
                    width: .fixed(seg.isSummary ? 36 : 20)
                )
                .foregroundStyle(seg.isAsset ? Color.designPrimaryFixedDim.opacity(seg.isSummary ? 0.9 : 0.65) : Color.designAccentRed.opacity(seg.isSummary ? 0.9 : 0.65))
                .cornerRadius(seg.isSummary ? 4 : 3)
            }

            ForEach(connectorData) { point in
                LineMark(
                    x: .value("", point.axisKey),
                    y: .value("", point.value)
                )
            }
            .foregroundStyle(Color.designPrimaryFixedDim.opacity(0.25))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 6]))

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.2))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let key = value.as(String.self) {
                        Text(labelMap[key] ?? key)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 100)
        .contentShape(Rectangle())
        .onTapGesture {
            // Mini 卡片没有坐标转换，简单方案：点图任意位置返回 L1
            if allocationDrilled != nil { allocationDrilled = nil }
        }
    }

    // MARK: - 预算消耗速率

    private var burnRateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                navigate(to: .budget)
            } label: {
                HStack {
                    Text("消耗速率")
                        .font(.designBodyMedium.weight(.bold))
                        .foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.burnRateData.isEmpty {
                Text("暂无数据")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                BurnRateBarChart(data: viewModel.burnRateData, progress: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 16)
    }

    // MARK: - 支出分类总览

    private var categoryOverviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                navigate(to: .category)
            } label: {
                HStack {
                    Text("支出分类")
                        .font(.designBodyMedium.weight(.bold))
                        .foregroundStyle(Color.designOnSurface)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            if viewModel.categoryOverviewItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.3))
                    Text("本月暂无支出")
                        .font(.designBodyMedium)
                        .foregroundStyle(Color.designOnSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                DonutChart(
                    categories: viewModel.categoryOverviewItems,
                    totalExpense: viewModel.categoryOverviewTotal,
                    centerTitle: String(localized: "本月支出"),
                    isDrilledDown: false,
                    showTopBar: false,
                    categoryType: .constant(.expense),
                    onCategoryTap: { _ in },
                    onCenterTap: { },
                    pieProgress: $categoryPieProgress,
                    explodedIndex: $categoryExplodedIndex,
                    hoveredIndex: $categoryHoveredIndex
                )
            }
        }
        .glassCard(cornerRadius: 20)
    }

    // MARK: - 最近交易

    private var recentTransactionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("最近交易")
                    .font(.designBodyMedium.weight(.bold))
                    .foregroundStyle(Color.designOnSurface)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if viewModel.recentTransactions.isEmpty {
                Text("本月暂无交易记录")
                    .font(.designBodyCaption)
                    .foregroundStyle(Color.designOnSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(viewModel.recentTransactions, id: \.objectID) { t in
                            Button {
                                selectedTransaction = t
                            } label: {
                                TransactionRowView(transaction: t)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 440)
            }
        }
        .glassCard(cornerRadius: 20)
    }

}

// MARK: - Privacy Placeholder Dot

private struct CircleDot: View {
    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(Color.designOnSurfaceVariant.opacity(isHovered ? 0.85 : 0.5))
            .frame(width: 12, height: 12)
            .offset(y: -6)
            .animation(.easeInOut(duration: 0.25), value: isHovered)
            .onHover { inside in
                isHovered = inside
            }
    }
}

