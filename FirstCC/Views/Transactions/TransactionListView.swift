import SwiftUI
@preconcurrency import CoreData

struct TransactionListOptions: OptionSet {
    let rawValue: Int
    static let hideCalendar   = TransactionListOptions(rawValue: 1 << 0)
    static let hideTypeFilter = TransactionListOptions(rawValue: 1 << 1)
    static let hideAddButton  = TransactionListOptions(rawValue: 1 << 2)
    /// 不画自身屏幕背景。列表上面还有同类控件（预算明细页的「本期/累计」分段条）时用：
    /// `.designScreen()` 的背景会 `.ignoresSafeArea()` 撑到整屏，压在兄弟节点上方接管触摸，
    /// 上方的分段条会变得看得见但点不动，卡片阴影也会被这层盖掉。
    static let hideScreenBackground = TransactionListOptions(rawValue: 1 << 3)
}

struct TransactionListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    var filterCategory: Category? = nil
    var options: TransactionListOptions = []
    /// 预过滤明细：非 nil 时直接渲染这批交易，跳过自身查询。
    /// 由调用方保证这批交易就是目标集合（预算项明细需要与金额统计共用同一套过滤规则）。
    var presetTransactions: [Transaction]? = nil
    /// 页面标题。nil 时沿用原行为：分类明细用分类名，其余用「流水」。
    var title: LocalizedStringKey? = nil
    @State private var transactions: [Transaction] = []
    @State private var showAddSheet = false
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date.now.startOfMonth
    @State private var selectedDay: Int?
    @State private var isCalendarExpanded = false
    /// 上一次上报的布局模式，用来区分「布局真的切了」和「页面重新出现又补报了一次」。
    @State private var lastLayoutMode: Bool?
    @State private var dailyExpense: [Int: Decimal] = [:]
    @State private var dailyIncome: [Int: Decimal] = [:]
    @State private var maxDailyExpense: Decimal = 0
    @State private var maxDailyIncome: Decimal = 0
    @State private var refreshVersion = 0
    @State private var monthlyIncome: Decimal = 0
    @State private var monthlyExpense: Decimal = 0
    @State private var monthTransactions: [Transaction] = []

    init(
        filterCategory: Category? = nil,
        options: TransactionListOptions = [],
        presetTransactions: [Transaction]? = nil,
        title: LocalizedStringKey? = nil
    ) {
        self.filterCategory = filterCategory
        self.options = options
        self.presetTransactions = presetTransactions
        self.title = title
    }

    /// 是否隐藏日历。预过滤模式下 `loadCalendarData` 直接 early-return，
    /// 热力图数据从未计算，所以有 preset 就必须隐藏，不能依赖调用方记得传 `.hideCalendar`
    private var calendarHidden: Bool {
        options.contains(.hideCalendar) || presetTransactions != nil
    }

    var body: some View {
        Group {
            if supportsTwoColumn {
                AdaptiveTwoColumnLayout(onModeChange: { isTwoColumn in
                    // 双栏左栏够宽，日历进横屏直接展开整月；退回单栏时恢复周条默认。
                    // 回调既会在模式变化时来，也会在页面重新出现时按当前模式补报一次
                    // （没有补报的话 iPad 横屏冷启动会漏掉初始值），所以要用 lastLayoutMode
                    // 去重：只有模式真的变了才重设——用户手动收起后切 tab 回来不会被顶开。
                    guard lastLayoutMode != isTwoColumn else { return }
                    lastLayoutMode = isTwoColumn
                    isCalendarExpanded = isTwoColumn
                }) { availableWidth in
                    twoColumnLayout(availableWidth: availableWidth)
                } compact: {
                    stackedLayout
                }
            } else {
                stackedLayout
            }
        }
        .if(!options.contains(.hideScreenBackground)) { $0.designScreen() }
        .safeAreaInset(edge: .bottom) {
            if !options.contains(.hideAddButton) {
                AddFloatingButton(title: "记一笔", identifier: "tx-add-button") {
                    showAddSheet = true
                }
            }
        }
        .navigationTitle(title ?? filterCategory.map { LocalizedStringKey($0.name) } ?? "流水")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let ledger = appContainer.currentLedger {
                    NavigationLink {
                        SearchView(viewModel: SearchViewModel(
                            ledger: ledger,
                            transactionService: appContainer.transactionService
                        ))
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            if !options.contains(.hideTypeFilter) {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("类型筛选", selection: $filterType) {
                        Text("全部").tag(Optional<TransactionType>.none)
                        Text(TransactionType.expense.displayName).tag(Optional<TransactionType>.some(.expense))
                        Text(TransactionType.income.displayName).tag(Optional<TransactionType>.some(.income))
                        Text(TransactionType.transfer.displayName).tag(Optional<TransactionType>.some(.transfer))
                        Text(TransactionType.lending.displayName).tag(Optional<TransactionType>.some(.lending))
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditTransactionView(prefillDate: resolvedSelectedDate)
        }
        .onAppear {
            loadCalendarData()
            applyFilters()
        }
        .onChange(of: selectedMonth) { _, _ in
            loadCalendarData()
            applyFilters()
        }
        .onChange(of: filterType) { _, _ in
            applyFilters()
        }
        .onChange(of: selectedDay) { _, _ in applyFilters() }
        .onChange(of: presetTransactions) { _, _ in
            loadCalendarData()
            applyFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: .transactionDidChange)) { _ in
            loadCalendarData()
            applyFilters()
            refreshVersion &+= 1
        }
    }

    // MARK: - Layout

    /// 只有主流水入口（默认参数）启用双栏。预算明细（`presetTransactions` / `.hideCalendar`）、
    /// 分类明细页都保持原来的单栏结构。
    ///
    /// 注意 `options.isEmpty` 是双栏左栏无条件渲染日历的**前提**：任何带选项的调用都进不了双栏，
    /// 所以不存在「日历该藏但左栏还在画」的组合。放宽这里时要一并处理 `calendarHidden`。
    private var supportsTwoColumn: Bool {
        options.isEmpty && filterCategory == nil && presetTransactions == nil
    }

    /// iPhone 竖屏 / iPad 竖屏 / 窄窗口：日历和列表在同一个 ScrollView 里，保持滚动收起日历的行为。
    private var stackedLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !calendarHidden {
                    calendarCard(collapsesOnDayTap: true)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                transactionRows
                    .padding(16)
            }
        }
        .id(refreshVersion)
        .modifier(ScrollCollapseModifier(isCalendarExpanded: $isCalendarExpanded))
    }

    /// 宽屏：左栏日历固定，右栏流水独立滚动。日历不跟随列表滚动，
    /// 所以不套 `ScrollCollapseModifier`——左右两栏各自独立才符合双栏的直觉。
    private func twoColumnLayout(availableWidth: CGFloat) -> some View {
        let leftWidth = TwoColumnLayout.leftWidth(
            for: availableWidth, fraction: 0.38, min: 360, max: 440
        )

        return HStack(alignment: .top, spacing: 20) {
            ScrollView {
                // 双栏左栏够宽，点选某天不收起成周条——否则用户每换一天都要再点开一次。
                calendarCard(collapsesOnDayTap: false)
                    .padding(.vertical, 16)
            }
            .scrollClipDisabled()
            .frame(width: leftWidth)

            ScrollView {
                // 只留纵向内边距：水平页边距由外层 HStack 统一给，栏内内容贴齐列边，
                // 与总览一致（左 16 / 栏距 20 / 右 16）。这里再加 16 会让右边距翻倍。
                transactionRows
                    .padding(.vertical, 16)
            }
            .id(refreshVersion)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
    }

    private func calendarCard(collapsesOnDayTap: Bool) -> some View {
        CalendarStripView(
            selectedMonth: $selectedMonth,
            selectedDay: $selectedDay,
            isExpanded: $isCalendarExpanded,
            dailyExpense: $dailyExpense,
            dailyIncome: $dailyIncome,
            maxDailyExpense: $maxDailyExpense,
            maxDailyIncome: $maxDailyIncome,
            monthlyIncome: $monthlyIncome,
            monthlyExpense: $monthlyExpense,
            collapsesOnDayTap: collapsesOnDayTap
        )
    }

    private var transactionRows: some View {
        LazyVStack(spacing: 12) {
            if transactions.isEmpty {
                ContentUnavailableView(
                    selectedDay != nil ? "当天没有交易记录" : "暂无交易记录",
                    systemImage: "tray",
                    description: Text("点击下方 + 开始记一笔")
                )
                .padding(.top, 40)
            } else {
                let fullSettlementIDs = Set(transactions.compactMap(\.reimbursedById))
                ForEach(groupedByDate) { group in
                    dateSectionHeader(title: group.title, transactions: group.transactions, fullMonthSettlementIDs: fullSettlementIDs)
                    ForEach(group.transactions, id: \.objectID) { transaction in
                        NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                            TransactionRowView(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tx-list-cell")
                    }
                }
            }
        }
        .accessibilityIdentifier("tx-list")
    }

    // MARK: - Date Section Header

    private func dateSectionHeader(title: String, transactions: [Transaction], fullMonthSettlementIDs: Set<UUID>) -> some View {
        let nonTransfer = transactions.filter { t in
            guard t.type != .transfer else { return false }
            if t.type == .expense, t.isReimbursable { return false }
            if t.type == .income, fullMonthSettlementIDs.contains(t.id) { return false }
            return true
        }
        let total = nonTransfer.reduce(Decimal.zero) { $0 + $1.ledgerAmount }
        let currencyCode = transactions.first?.ledger?.defaultCurrencyCode ?? "CNY"

        return HStack(spacing: 8) {
            Circle()
                .fill(Color.designPrimaryContainer)
                .frame(width: 6, height: 6)

            // 标题已在 dayGroupTitle 里本地化过，这里直接用 String 渲染；
            // 再包一层 LocalizedStringKey 会拿"已经翻译好的文本"去查一次表。
            Text(title)
                .font(.custom("SpaceGrotesk-Medium", fixedSize: 14))
                .foregroundStyle(Color.designOnSurfaceVariant)

            Text("流水")
                .font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.6))

            Spacer()

            if !nonTransfer.isEmpty {
                Text("合计：")
                    .font(.custom("SpaceGrotesk-Medium", fixedSize: 12))
                    .foregroundStyle(Color.designOnSurfaceVariant.opacity(0.5))
                    +
                Text(total > 0 ? "+\(CurrencyFormatter.formatDecimal(amount: total, currencyCode: currencyCode))" : total < 0 ? "-\(CurrencyFormatter.formatDecimal(amount: total, currencyCode: currencyCode, showAbs: true))" : CurrencyFormatter.formatDecimal(amount: total, currencyCode: currencyCode))
                    .font(.custom("JetBrainsMono-Medium", fixedSize: 12))
                    .foregroundStyle(total > 0 ? Color.designPrimaryFixedDim : total < 0 ? Color.designAccentRed : Color.designOnSurfaceVariant)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Grouping

    private var resolvedSelectedDate: Date? {
        guard let day = selectedDay else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month], from: selectedMonth)
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    private var groupedByDate: [TransactionDayGroup] {
        transactions.groupedByDay()
    }

    // MARK: - Data Loading

    private func loadCalendarData() {
        guard let ledger = appContainer.currentLedger else { return }
        let cal = Calendar.current

        // 预过滤模式：调用方（预算项明细）已按金额口径过滤，直接渲染，避免两套过滤规则产生差异
        if let preset = presetTransactions {
            monthTransactions = preset
            return
        }

        let start = selectedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        var filters = TransactionFilters()
        filters.dateRange = start..<end
        let all = (try? appContainer.transactionService.fetchTransactions(for: ledger, context: modelContext, filters: filters)) ?? []

        let normal = all
            .excludingReimbursementTransactions()

        let calData = filterCategory.map { cat in
            let ids = cat.selfAndDescendantIDs
            return normal.filter { $0.belongs(toCategoryIDs: ids) }
        } ?? normal

        var expenseByDay: [Int: Decimal] = [:]
        var incomeByDay: [Int: Decimal] = [:]
        var totalIncome: Decimal = 0
        var totalExpense: Decimal = 0

        for t in calData {
            let d = cal.component(.day, from: t.date)
            switch t.type {
            case .expense:
                let amt = t.netExpenseAmount
                expenseByDay[d, default: 0] += amt
                totalExpense += amt
            case .income:
                let incAmt = t.ledgerAmount
                incomeByDay[d, default: 0] += incAmt
                totalIncome += incAmt
            default:
                break
            }
        }

        dailyExpense = expenseByDay
        dailyIncome = incomeByDay
        maxDailyExpense = expenseByDay.values.max() ?? 0
        maxDailyIncome = incomeByDay.values.max() ?? 0
        monthlyIncome = totalIncome
        monthlyExpense = totalExpense
        monthTransactions = all.deduplicatingTransfers()
    }

    private func applyFilters() {
        var result = monthTransactions
        if let day = selectedDay {
            let cal = Calendar.current
            result = result.filter { cal.component(.day, from: $0.date) == day }
        }
        if let type = filterType {
            result = result.filter { $0.type == type }
        }
        // 预过滤模式下调用方已按分类口径过滤，这里不再重复过滤——两套规则会漂移
        if presetTransactions == nil, let cat = filterCategory {
            let ids = cat.selfAndDescendantIDs
            result = result.filter { $0.belongs(toCategoryIDs: ids) }
        }
        transactions = result
    }
}

// MARK: - Scroll Collapse (iOS 18+)

private struct ScrollCollapseModifier: ViewModifier {
    @Binding var isCalendarExpanded: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { oldY, newY in
                if newY < oldY - 10, isCalendarExpanded {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isCalendarExpanded = false
                    }
                }
            }
        } else {
            content
        }
    }
}
