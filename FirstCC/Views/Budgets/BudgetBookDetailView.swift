import SwiftUI
@preconcurrency import CoreData

struct BudgetBookDetailView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let book: BudgetBook

    @State private var selectedMonth: Date = Date()
    @State private var items: [BudgetItem] = []
    @State private var showAddSheet = false
    @State private var editingItem: BudgetItem?
    @State private var cumulativeSpent: [UUID: Decimal] = [:]
    @State private var periodSpent: [UUID: Decimal] = [:]
    @State private var unbudgetedCategories: [(Category, Decimal)] = []
    @State private var totalUnbudgeted: Decimal = 0
    @State private var preselectedCategory: Category?
    // Animated progress values for summary card
    @State private var animTotalCumulative: Decimal = 0
    @State private var animTotalPeriod: Decimal = 0
    @State private var navCategory: Category?
    @State private var deleteCandidate: BudgetItem?
    @State private var showMonthPicker = false

    /// 是否在查看历史月份（当月及以前，不含未来）
    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    /// 所选月份的自然月范围，与账本起始日取交集
    private var monthRange: ClosedRange<Date> {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? selectedMonth
        let rangeStart = max(cal.startOfDay(for: monthStart), cal.startOfDay(for: book.startDate))
        let rangeEnd = max(rangeStart, cal.endOfDay(for: monthEnd))
        return rangeStart...rangeEnd
    }

    /// 累计区间：账本起始日到所选月末
    private var cumulativeRange: ClosedRange<Date> {
        let cal = Calendar.current
        let rangeEnd = cal.endOfDay(for: monthRange.upperBound)
        return cal.startOfDay(for: book.startDate)...rangeEnd
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return f
    }()

    private var monthDisplayText: String {
        Self.monthFormatter.string(from: selectedMonth)
    }

    var body: some View {
        List {
            Section("概览") {
                summaryCard
            }

            Section("预算项") {
                if items.isEmpty {
                    Text("暂无预算项，点击右上角 + 添加")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    itemRow(item)
                        .swipeActions(edge: .leading) {
                            Button { editingItem = item } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                            .disabled(!isCurrentMonth)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCandidate = item
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .disabled(!isCurrentMonth)
                        }
                }
            }

            if !unbudgetedCategories.isEmpty {
                Section("非预算项") {
                    ForEach(unbudgetedCategories, id: \.0.id) { cat, spent in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: cat.iconName)
                                    .foregroundStyle(Color(hex: cat.colorHex))
                                Text(LocalizedStringKey(cat.name))
                                Spacer()
                            }
                            budgetSpendingLine(label: "本期", spent: spent, budget: totalUnbudgeted, currency: currency)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { preselectedCategory = cat }
                    }
                    HStack {
                        Text("合计")
                            .font(.designBodyMedium)
                        Spacer()
                        CurrencyText(amount: totalUnbudgeted, currencyCode: currency, size: 13, foregroundColor: .red)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .navigationTitle(book.name)
        .toolbar {
            ToolbarItem(placement: .principal) {
                monthNavigator
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isCurrentMonth)
            }
        }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadData() }) {
            AddEditBudgetItemView(book: book)
        }
        .sheet(item: $editingItem, onDismiss: { loadData() }) { item in
            AddEditBudgetItemView(editing: item, book: book)
        }
        .sheet(item: $preselectedCategory, onDismiss: { loadData() }) { cat in
            AddEditBudgetItemView(book: book, preselectedCategory: cat)
        }
        .onAppear(perform: loadData)
        .navigationDestination(item: $navCategory) { cat in
            TransactionListView(filterCategory: cat, options: [.hideTypeFilter, .hideAddButton])
        }
        .confirmationDialog("确定删除此预算项？", isPresented: showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let item = deleteCandidate {
                    items = []
                    try? appContainer.budgetService.deleteItem(item, context: modelContext)
                    loadData()
                }
                deleteCandidate = nil
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        }
    }

    // MARK: - Month Navigator

    /// 是否已到可导航的最早月份（账本起始月）
    private var isAtOldestMonth: Bool {
        let cal = Calendar.current
        let bookStartMonth = cal.date(from: cal.dateComponents([.year, .month], from: book.startDate)) ?? book.startDate
        let selectedMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        return selectedMonthStart <= bookStartMonth
    }

    private var monthNavigator: some View {
        HStack(spacing: 4) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.designBodyMedium)
            }
            .buttonStyle(.plain)
            .disabled(isAtOldestMonth)

            Button {
                showMonthPicker = true
            } label: {
                Text(monthDisplayText)
                    .font(.designBodyMedium)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showMonthPicker, onDismiss: { loadData() }) {
                MonthYearPicker(selectedMonth: $selectedMonth, minDate: book.startDate, maxDate: Date())
                    .presentationDetents([.medium])
            }

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.designBodyMedium)
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
        }
    }

    private func moveMonth(by value: Int) {
        let cal = Calendar.current
        guard let newMonth = cal.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        selectedMonth = newMonth
        loadData()
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let totalBudget = appContainer.budgetService.totalBudget(for: book)
        let periodBudget = appContainer.budgetService.totalCurrentPeriodBudget(for: book)

        return VStack(spacing: 12) {
            budgetSummaryBlock(
                label: "本期支出",
                spent: animTotalPeriod,
                budget: periodBudget,
                currency: currency
            )
            Divider()
            budgetSummaryBlock(
                label: "累计支出",
                spent: animTotalCumulative,
                budget: totalBudget,
                currency: currency
            )
        }
        .padding(.vertical, 4)
    }

    private func budgetSummaryBlock(label: LocalizedStringKey, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        let progress = min(ratio, 1.0)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.designBodyMedium)
                Spacer()
                CurrencyText(amount: spent, currencyCode: currency, size: 15, foregroundColor: ratio > 1.0 ? .red : .primary)
                    .fontWeight(.medium)
                Text("/")
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
                CurrencyText(amount: budget, currencyCode: currency, size: 12, foregroundColor: .secondary)
                Text("\(Int(pct))%")
                    .font(.designBodySmall)
                    .foregroundStyle(progressColor(ratio))
            }
            if budget > 0 {
                PixelProgressBar(progress: progress, tint: progressColor(ratio))
            }
        }
    }

    // MARK: - Item Row

    private func itemRow(_ item: BudgetItem) -> some View {
        let cumSpent = cumulativeSpent[item.id] ?? 0
        let perSpent = periodSpent[item.id] ?? 0
        let totalBgt = item.totalBudget
        let periodBgt = item.periodBudget

        let rowContent = VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let cat = item.category {
                    Image(systemName: cat.iconName)
                        .foregroundStyle(Color(hex: cat.colorHex))
                    Text(LocalizedStringKey(cat.name))
                } else {
                    Image(systemName: "chart.pie")
                        .foregroundStyle(Color.designPrimaryContainer)
                    Text("未分类")
                }
                Spacer()
                Text(item.period.displayName)
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
            }
            budgetSpendingLine(label: "本期", spent: perSpent, budget: periodBgt, currency: currency)
            budgetSpendingLine(label: "累计", spent: cumSpent, budget: totalBgt, currency: currency)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        return Group {
            if let cat = item.category {
                rowContent.onTapGesture { navCategory = cat }
            } else {
                rowContent.onTapGesture { editingItem = item }
            }
        }
    }

    private func budgetSpendingLine(label: LocalizedStringKey, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        let progress = min(ratio, 1.0)

        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
                Spacer()
                CurrencyText(amount: spent, currencyCode: currency, size: 12, foregroundColor: ratio > 1.0 ? .red : .primary)
                    .fontWeight(.medium)
                Text("/")
                    .font(.designBodySmall)
                    .foregroundStyle(.secondary)
                CurrencyText(amount: budget, currencyCode: currency, size: 11, foregroundColor: .secondary)
                Text("\(Int(pct))%")
                    .font(.designBodySmall)
                    .foregroundStyle(progressColor(ratio))
            }
            if budget > 0 {
                PixelProgressBar(progress: progress, tint: progressColor(ratio))
            }
        }
    }

    private func progressColor(_ progress: Double) -> Color {
        Color.progressTint(for: progress)
    }

    private var currency: String { book.ledger?.defaultCurrencyCode ?? "CNY" }
    private var showDeleteConfirm: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    // MARK: - Load Data

    private func loadData() {
        let newItems = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
        // 排序：一级分类在上，其子分类紧跟在下方；同级按名称排序
        let budgetedCatIDs = Set(newItems.compactMap { $0.category?.id })
        let catNameByID: [UUID: String] = Dictionary(uniqueKeysWithValues: newItems.compactMap { item in
            item.category.flatMap { ($0.id, $0.name) }
        })
        var sortKeys: [UUID: String] = [:]
        for item in newItems {
            guard let cat = item.category else { continue }
            if let ancestorID = cat.allAncestorIDs.first(where: { budgetedCatIDs.contains($0) }) {
                sortKeys[cat.id] = (catNameByID[ancestorID] ?? "") + cat.name
            } else {
                sortKeys[cat.id] = cat.name
            }
        }
        let sortedItems = newItems.sorted { a, b in
            let keyA = a.category.flatMap { sortKeys[$0.id] } ?? ""
            let keyB = b.category.flatMap { sortKeys[$0.id] } ?? ""
            return (keyA as NSString).localizedStandardCompare(keyB) == .orderedAscending
        }

        let cumDict = appContainer.budgetService.categorySpending(in: cumulativeRange, for: book, context: modelContext)
        let perDict = appContainer.budgetService.categorySpending(in: monthRange, for: book, context: modelContext)
        var newCumulative: [UUID: Decimal] = [:]
        var newPeriod: [UUID: Decimal] = [:]
        for item in sortedItems {
            let catID = item.category?.id
            newCumulative[item.id] = catID.flatMap { cumDict[$0] } ?? 0
            newPeriod[item.id] = catID.flatMap { perDict[$0] } ?? 0
        }
        let newUnbudgeted = appContainer.budgetService.unbudgetedCategorySpending(in: monthRange, for: book, context: modelContext)
        let newTotalUnbudgeted = newUnbudgeted.reduce(0) { $0 + $1.1 }
        // 累计支出：从账本起始日到所选月末
        let newTotalCumulative = appContainer.budgetService.totalCumulativeSpending(in: cumulativeRange, for: book, context: modelContext)
        // 本期支出：所选月份
        let newTotalPeriod = appContainer.budgetService.totalCurrentPeriodSpending(in: monthRange, for: book, context: modelContext)

        // 先清空触发动画重置，再动画更新
        items = sortedItems
        cumulativeSpent = [:]
        periodSpent = [:]
        animTotalCumulative = 0
        animTotalPeriod = 0
        unbudgetedCategories = []
        totalUnbudgeted = 0
        withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) {
            cumulativeSpent = newCumulative
            periodSpent = newPeriod
            animTotalCumulative = newTotalCumulative
            animTotalPeriod = newTotalPeriod
            unbudgetedCategories = newUnbudgeted
            totalUnbudgeted = newTotalUnbudgeted
        }
    }
}

// MARK: - Month Year Picker

struct MonthYearPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMonth: Date
    let minDate: Date
    let maxDate: Date

    private static let months = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]

    private var minYear: Int {
        Calendar.current.component(.year, from: minDate)
    }

    private var maxYear: Int {
        Calendar.current.component(.year, from: maxDate)
    }

    private var selectedYear: Int {
        Calendar.current.component(.year, from: selectedMonth)
    }

    private var selectedMonthIndex: Int {
        Calendar.current.component(.month, from: selectedMonth) - 1
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Picker("月份", selection: Binding(
                    get: { selectedMonthIndex },
                    set: { monthIndex in
                        var components = Calendar.current.dateComponents([.year], from: selectedMonth)
                        components.month = monthIndex + 1
                        if let newDate = Calendar.current.date(from: components) {
                            selectedMonth = min(newDate, maxDate)
                        }
                    }
                )) {
                    ForEach(0..<12, id: \.self) { index in
                        Text(Self.months[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)

                Picker("年份", selection: Binding(
                    get: { selectedYear },
                    set: { year in
                        var components = Calendar.current.dateComponents([.month], from: selectedMonth)
                        components.year = year
                        if let newDate = Calendar.current.date(from: components) {
                            selectedMonth = min(newDate, maxDate)
                        }
                    }
                )) {
                    ForEach(minYear...maxYear, id: \.self) { year in
                        Text("\(year)年").tag(year)
                    }
                }
                .pickerStyle(.menu)
            }

            Button("确定") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 240)
    }
}

