import SwiftUI
@preconcurrency import CoreData

// MARK: - Shared Helpers

private struct BudgetSpendingLine: View {
    let label: LocalizedStringKey
    let spent: Decimal
    let budget: Decimal
    let currency: String
    var onTap: (() -> Void)? = nil

    @State private var animRatio: Double = 0
    @State private var isHovered = false

    var body: some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.designBodySmall).foregroundStyle(.secondary)
                Spacer()
                CurrencyText(amount: spent, currencyCode: currency, size: 12, foregroundColor: ratio > 1.0 ? .designAccentRed : Color.designOnSurface)
                Text("/").font(.designBodySmall).foregroundStyle(.secondary)
                CurrencyText(amount: budget, currencyCode: currency, size: 11, foregroundColor: .secondary)
                Text("\(Int(pct))%").font(.designBodySmall).foregroundStyle(Color.progressTint(for: ratio))
            }
            if budget > 0 {
                PixelProgressBar(progress: min(animRatio, 1.0), tint: Color.progressTint(for: ratio))
            }
        }
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.designAccentGreen.opacity(isHovered ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .onHover { inside in
            // 仅可点击的进度线给出悬停反馈（非预算项行无 onTap）
            guard onTap != nil else { return }
            withAnimation(.easeOut(duration: 0.12)) { isHovered = inside }
            // 用 set 而非 push/pop：行被移出层级时不会有未配对的 pop 把光标卡住
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onDisappear {
            // 悬停中行被移除（切 scope / 删除）时 onHover(false) 不会触发，光标会卡在 pointingHand
            if onTap != nil { NSCursor.arrow.set() }
        }
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                animRatio = ratio
            }
        }
        .onChange(of: ratio) { _, new in
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) {
                animRatio = new
            }
        }
    }
}

// MARK: - Main View

struct BudgetBookDetailMacView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let book: BudgetBook
    @State private var items: [BudgetItem] = []
    @State private var cumulative: [UUID: Decimal] = [:]
    @State private var period: [UUID: Decimal] = [:]
    @State private var unbudgetedCategories: [(Category, Decimal)] = []
    @State private var totalUnbudgeted: Decimal = 0
    @State private var showAddSheet = false
    @State private var editingItem: BudgetItem?
    @State private var preselectedCategory: Category?
    @State private var deleteCandidate: BudgetItem?
    @State private var showDeleteConfirm = false
    @State private var navBudgetEntry: BudgetItemNavEntry?

    var body: some View {
        let currency = book.ledger?.defaultCurrencyCode ?? "CNY"
        let totalBudget = appContainer.budgetService.totalBudget(for: book)
        let totalCumulative = appContainer.budgetService.totalCumulativeSpending(for: book, context: modelContext)
        let totalPeriod = appContainer.budgetService.totalCurrentPeriodSpending(for: book, context: modelContext)
        let periodBudget = appContainer.budgetService.totalCurrentPeriodBudget(for: book)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard(totalPeriod: totalPeriod, periodBudget: periodBudget,
                                totalCumulative: totalCumulative, totalBudget: totalBudget,
                                currency: currency)
                    budgetItemsCard(currency: currency)
                    if !unbudgetedCategories.isEmpty {
                        unbudgetedCard(currency: currency)
                    }
                }
                .padding(24)
            }
            .designScreen()
            .navigationTitle(book.name)
            .navigationDestination(item: $navBudgetEntry) { navEntry in
                BudgetItemTransactionListMacView(entry: navEntry) {
                    navBudgetEntry = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.glassTextButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 500)
        .onAppear { loadData() }
        .sheet(isPresented: $showAddSheet, onDismiss: { loadData() }) {
            AddEditBudgetItemView(book: book)
        }
        .sheet(item: $editingItem, onDismiss: { loadData() }) { item in
            AddEditBudgetItemView(editing: item, book: book)
        }
        .sheet(item: $preselectedCategory, onDismiss: { loadData() }) { cat in
            AddEditBudgetItemView(book: book, preselectedCategory: cat)
        }
        .confirmationDialog("确定删除此预算项？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let item = deleteCandidate {
                    items = []
                    do {
                        try appContainer.budgetService.deleteItem(item, context: modelContext)
                        loadData()
                    } catch {
                        DiagnosticLog.log("BudgetBookDetailMac: delete item FAILED \(error.localizedDescription)")
                    }
                }
                deleteCandidate = nil
                showDeleteConfirm = false
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        }
    }

    // MARK: - Cards

    private func summaryCard(totalPeriod: Decimal, periodBudget: Decimal,
                             totalCumulative: Decimal, totalBudget: Decimal,
                             currency: String) -> some View {
        VStack(spacing: 12) {
            Text("概览").font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant).tracking(1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
            budgetLine(label: "本期支出", spent: totalPeriod, budget: periodBudget, currency: currency)
            Divider().opacity(0.3)
            budgetLine(label: "累计支出", spent: totalCumulative, budget: totalBudget, currency: currency)
        }
        .padding(16).glassCard(cornerRadius: 16)
    }

    private func budgetItemsCard(currency: String) -> some View {
        VStack(spacing: 12) {
            Text("预算项").font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant).tracking(1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if items.isEmpty {
                Text("暂无预算项，点击右上角 + 添加")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(items) { item in
                    BudgetItemRowView(
                        item: item,
                        currency: currency,
                        cumSpent: cumulative[item.id] ?? 0,
                        perSpent: period[item.id] ?? 0,
                        navBudgetEntry: $navBudgetEntry,
                        editingItem: $editingItem,
                        deleteCandidate: $deleteCandidate,
                        showDeleteConfirm: $showDeleteConfirm
                    )
                    .contextMenu {
                        Button { editingItem = item } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteCandidate = item; showDeleteConfirm = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    if item.id != items.last?.id { Divider().opacity(0.2) }
                }
            }
        }
        .padding(16).glassCard(cornerRadius: 16)
    }

    private func unbudgetedCard(currency: String) -> some View {
        VStack(spacing: 12) {
            Text("非预算项").font(.designLabel)
                .foregroundStyle(Color.designOnSurfaceVariant).tracking(1.0)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(unbudgetedCategories, id: \.0.id) { cat, spent in
                HStack {
                    Image(systemName: cat.iconName)
                        .foregroundStyle(Color(hex: cat.colorHex))
                    Text(LocalizedStringKey(cat.name))
                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { preselectedCategory = cat }
                BudgetSpendingLine(label: "本期", spent: spent, budget: totalUnbudgeted, currency: currency)
                if cat.id != unbudgetedCategories.last?.0.id { Divider().opacity(0.2) }
            }
            HStack {
                Text("合计").font(.designBodyMedium)
                Spacer()
                CurrencyText(amount: totalUnbudgeted, currencyCode: currency, size: 13, foregroundColor: .designAccentRed)
                    .fontWeight(.semibold)
            }
        }
        .padding(16).glassCard(cornerRadius: 16)
    }

    // MARK: - Helpers

    private func budgetLine(label: LocalizedStringKey, spent: Decimal, budget: Decimal, currency: String) -> some View {
        BudgetSpendingLine(label: label, spent: spent, budget: budget, currency: currency)
    }

    private func loadData() {
        let newItems = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
        // 排序：一级分类在上，其子分类紧跟在下方；同级按名称排序
        // 预构建排序键映射，避免在 sorted 比较器内 O(n) 扫描
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
        items = newItems.sorted { a, b in
            let keyA = a.category.flatMap { sortKeys[$0.id] } ?? ""
            let keyB = b.category.flatMap { sortKeys[$0.id] } ?? ""
            return (keyA as NSString).localizedStandardCompare(keyB) == .orderedAscending
        }
        for item in items {
            cumulative[item.id] = appContainer.budgetService.cumulativeSpending(for: item, context: modelContext)
            period[item.id] = appContainer.budgetService.currentPeriodSpending(for: item, context: modelContext)
        }
        unbudgetedCategories = appContainer.budgetService.unbudgetedCategorySpending(for: book, context: modelContext)
        totalUnbudgeted = unbudgetedCategories.reduce(0) { $0 + $1.1 }
    }

}

// MARK: - Budget Item Row (hover-aware)

private struct BudgetItemRowView: View {
    let item: BudgetItem
    let currency: String
    let cumSpent: Decimal
    let perSpent: Decimal
    @Binding var navBudgetEntry: BudgetItemNavEntry?
    @Binding var editingItem: BudgetItem?
    @Binding var deleteCandidate: BudgetItem?
    @Binding var showDeleteConfirm: Bool

    @State private var isHovered = false

    var body: some View {
        let periodEntry = BudgetItemNavEntry(item: item, scope: .currentPeriod)
        let cumulativeEntry = BudgetItemNavEntry(item: item, scope: .cumulative)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let cat = item.category {
                    Image(systemName: cat.iconName)
                        .foregroundStyle(Color(hex: cat.colorHex))
                    Text(LocalizedStringKey(cat.name))
                        .font(.designBodySmall)
                        .foregroundStyle(Color.designOnSurface)
                } else {
                    Image(systemName: "chart.pie")
                        .foregroundStyle(Color.designPrimaryContainer)
                    Text("未分类").font(.designBodySmall)
                }
                Spacer()

                if isHovered {
                    HStack(spacing: 4) {
                        Button { editingItem = item } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(DesignGlassCircleButton())
                        .help("编辑")

                        Button { deleteCandidate = item; showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(DesignGlassCircleButton())
                        .help("删除")
                    }
                } else {
                    Text(item.period.displayName)
                        .font(.designBodyCaption)
                        .foregroundStyle(.secondary)
                }
            }

            BudgetSpendingLine(label: "本期", spent: perSpent, budget: item.periodBudget, currency: currency) {
                navBudgetEntry = periodEntry
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { navBudgetEntry = periodEntry }

            BudgetSpendingLine(label: "累计", spent: cumSpent, budget: item.totalBudget, currency: currency) {
                navBudgetEntry = cumulativeEntry
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { navBudgetEntry = cumulativeEntry }
        }
        .padding(.vertical, 2)
        // 保持整行热区：onHover 与手势一样按 content shape 命中，
        // 否则两行进度线之间的间隙会让编辑/删除按钮中途消失
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = inside }
        }
    }
}
