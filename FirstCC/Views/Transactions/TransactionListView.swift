import SwiftUI
@preconcurrency import CoreData

struct TransactionListOptions: OptionSet {
    let rawValue: Int
    static let hideCalendar   = TransactionListOptions(rawValue: 1 << 0)
    static let hideTypeFilter = TransactionListOptions(rawValue: 1 << 1)
    static let hideAddButton  = TransactionListOptions(rawValue: 1 << 2)
}

struct TransactionListView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.managedObjectContext) private var modelContext
    var filterCategory: Category? = nil
    var options: TransactionListOptions = []
    /// 预过滤明细：非 nil 时直接渲染这批交易，跳过自身查询。
    /// 由调用方保证这批交易就是目标集合（预算项明细需要与金额统计共用同一套过滤规则）。
    var presetTransactions: [Transaction]? = nil
    @State private var transactions: [Transaction] = []
    @State private var showAddSheet = false
    @State private var filterType: TransactionType?
    @State private var selectedMonth: Date = Date.now.startOfMonth
    @State private var selectedDay: Int?
    @State private var isCalendarExpanded = false
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
        presetTransactions: [Transaction]? = nil
    ) {
        self.filterCategory = filterCategory
        self.options = options
        self.presetTransactions = presetTransactions
    }

    /// 是否隐藏日历。预过滤模式下 `loadCalendarData` 直接 early-return，
    /// 热力图数据从未计算，所以有 preset 就必须隐藏，不能依赖调用方记得传 `.hideCalendar`
    private var calendarHidden: Bool {
        options.contains(.hideCalendar) || presetTransactions != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !calendarHidden {
                    CalendarStripView(
                        selectedMonth: $selectedMonth,
                        selectedDay: $selectedDay,
                        isExpanded: $isCalendarExpanded,
                        dailyExpense: $dailyExpense,
                        dailyIncome: $dailyIncome,
                        maxDailyExpense: $maxDailyExpense,
                        maxDailyIncome: $maxDailyIncome,
                        monthlyIncome: $monthlyIncome,
                        monthlyExpense: $monthlyExpense
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                LazyVStack(spacing: 12) {
                    if transactions.isEmpty {
                        ContentUnavailableView(
                            selectedDay != nil ? "当天没有交易记录" : "暂无交易记录",
                            systemImage: "tray",
                            description: Text("点击右上角 + 开始记一笔")
                        )
                        .padding(.top, 40)
                    } else {
                        let fullSettlementIDs = Set(transactions.compactMap(\.reimbursedById))
                        ForEach(groupedByDate, id: \.key) { group in
                            dateSectionHeader(dateKey: group.key, transactions: group.value, fullMonthSettlementIDs: fullSettlementIDs)
                            ForEach(group.value, id: \.objectID) { transaction in
                                NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                                    TransactionRowView(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("tx-list-cell")
                            }
                        }
                    }
                }
                .padding(16)
                .accessibilityIdentifier("tx-list")
            }
        }
        .id(refreshVersion)
        .modifier(ScrollCollapseModifier(isCalendarExpanded: $isCalendarExpanded))
        .designScreen()
        .navigationTitle(filterCategory.map { LocalizedStringKey($0.name) } ?? "流水")
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
            if !options.contains(.hideAddButton) {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("记一笔"))
                    .accessibilityIdentifier("tx-add-button")
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

    // MARK: - Date Section Header

    private func dateSectionHeader(dateKey: String, transactions: [Transaction], fullMonthSettlementIDs: Set<UUID>) -> some View {
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

            Text(LocalizedStringKey(dateKey))
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

    private static let dateGroupLocale = Locale(identifier: "zh_CN")

    private var resolvedSelectedDate: Date? {
        guard let day = selectedDay else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month], from: selectedMonth)
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    private var groupedByDate: [(key: String, value: [Transaction])] {
        transactions.groupedByRelativeDate(locale: Self.dateGroupLocale)
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
