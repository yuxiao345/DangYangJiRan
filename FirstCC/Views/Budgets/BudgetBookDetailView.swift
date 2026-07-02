import SwiftUI
@preconcurrency import CoreData

struct BudgetBookDetailView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let book: BudgetBook
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
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCandidate = item
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
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
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
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
                    items = []  // 先清空数组，防止 ForEach 在布局更新时访问已删除的 CoreData 对象导致 crash
                    try? appContainer.budgetService.deleteItem(item, context: modelContext)
                    loadData()
                }
                deleteCandidate = nil
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        }
    }

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

    private func budgetSummaryBlock(label: String, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        let progress = min(ratio, 1.0)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(label))
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

    private func budgetSpendingLine(label: String, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        let progress = min(ratio, 1.0)

        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(label))
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
        if progress > 1.0 { return .red }
        switch progress {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .orange
        }
    }

    private var currency: String { book.ledger?.defaultCurrencyCode ?? "CNY" }
    private var showDeleteConfirm: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    private func loadData() {
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? now
        let rangeStart = max(cal.startOfDay(for: monthStart), cal.startOfDay(for: book.startDate))
        let rangeEnd = max(rangeStart, cal.endOfDay(for: monthEnd))
        let monthRange = rangeStart...rangeEnd

        let newItems = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
        let cumDict = appContainer.budgetService.categorySpending(in: cal.startOfDay(for: book.startDate)...Date(), for: book, context: modelContext)
        let perDict = appContainer.budgetService.categorySpending(in: monthRange, for: book, context: modelContext)
        var newCumulative: [UUID: Decimal] = [:]
        var newPeriod: [UUID: Decimal] = [:]
        for item in newItems {
            let catID = item.category?.id
            newCumulative[item.id] = catID.flatMap { cumDict[$0] } ?? 0
            newPeriod[item.id] = catID.flatMap { perDict[$0] } ?? 0
        }
        let newUnbudgeted = appContainer.budgetService.unbudgetedCategorySpending(for: book, context: modelContext)
        let newTotalUnbudgeted = newUnbudgeted.reduce(0) { $0 + $1.1 }
        // 从 categorySpending 结果直接求和，避免重复 fetch
        let newTotalCumulative = cumDict.values.reduce(0, +)
        let newTotalPeriod = perDict.values.reduce(0, +)

        // 先渲染 0 状态列表，下一帧用 spring 驱动 Animatable 进度条
        items = newItems
        cumulativeSpent = [:]
        periodSpent = [:]
        animTotalCumulative = 0
        animTotalPeriod = 0
        unbudgetedCategories = []
        totalUnbudgeted = 0
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.65)) {
                self.cumulativeSpent = newCumulative
                self.periodSpent = newPeriod
                self.animTotalCumulative = newTotalCumulative
                self.animTotalPeriod = newTotalPeriod
                self.unbudgetedCategories = newUnbudgeted
                self.totalUnbudgeted = newTotalUnbudgeted
            }
        }
    }
}
