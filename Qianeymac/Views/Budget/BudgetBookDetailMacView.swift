import SwiftUI
@preconcurrency import CoreData

// MARK: - Shared Helpers

private struct BudgetSpendingLine: View {
    let label: String
    let spent: Decimal
    let budget: Decimal
    let currency: String

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
                Text("\(Int(pct))%").font(.designBodySmall).foregroundStyle(progressColor(ratio))
            }
            if budget > 0 {
                PixelProgressBar(progress: min(ratio, 1.0), tint: progressColor(ratio))
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
    @State private var navCategory: Category?

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
            .navigationDestination(item: $navCategory) { cat in
                TransactionListContent(filterCategory: cat, options: [.hideCalendar, .hideTypeFilter, .hideAddButton])
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
        .confirmationDialog("确定删除此预算项？", isPresented: showDeleteConfirm) {
            Button("删除", role: .destructive) {
                if let item = deleteCandidate {
                    do {
                        try appContainer.budgetService.deleteItem(item, context: modelContext)
                        loadData()
                    } catch {
                        DiagnosticLog.log("BudgetBookDetailMac: delete item FAILED \(error.localizedDescription)")
                    }
                }
                deleteCandidate = nil
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
                        navCategory: $navCategory,
                        editingItem: $editingItem,
                        deleteCandidate: $deleteCandidate
                    )
                    .contextMenu {
                        Button { editingItem = item } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteCandidate = item
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

    private func budgetLine(label: String, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.designBodyMedium)
                Spacer()
                CurrencyText(amount: spent, currencyCode: currency, size: 15, foregroundColor: ratio > 1.0 ? .designAccentRed : Color.designOnSurface)
                Text("/").font(.designBodySmall).foregroundStyle(.secondary)
                CurrencyText(amount: budget, currencyCode: currency, size: 12, foregroundColor: .secondary)
                Text("\(Int(pct))%").font(.designBodySmall).foregroundStyle(progressColor(ratio))
            }
            if budget > 0 {
                PixelProgressBar(progress: min(ratio, 1.0), tint: progressColor(ratio))
            }
        }
    }

    private func loadData() {
        items = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
        for item in items {
            cumulative[item.id] = appContainer.budgetService.cumulativeSpending(for: item, context: modelContext)
            period[item.id] = appContainer.budgetService.currentPeriodSpending(for: item, context: modelContext)
        }
        unbudgetedCategories = appContainer.budgetService.unbudgetedCategorySpending(for: book, context: modelContext)
        totalUnbudgeted = unbudgetedCategories.reduce(0) { $0 + $1.1 }
    }

    private var showDeleteConfirm: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }
}

// MARK: - Budget Item Row (hover-aware)

private struct BudgetItemRowView: View {
    let item: BudgetItem
    let currency: String
    let cumSpent: Decimal
    let perSpent: Decimal
    @Binding var navCategory: Category?
    @Binding var editingItem: BudgetItem?
    @Binding var deleteCandidate: BudgetItem?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let cat = item.category {
                    Image(systemName: cat.iconName)
                        .foregroundStyle(Color(hex: cat.colorHex))
                    Text(LocalizedStringKey(cat.name))
                        .font(.designBodySmall)
                        .foregroundStyle(isHovered ? Color.designAccentGreen : Color.designOnSurface)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.designOnSurfaceVariant.opacity(isHovered ? 0.6 : 0))
                        .offset(x: isHovered ? 2 : -4)
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
                        .buttonStyle(.borderless)
                        .help("编辑")

                        Button { deleteCandidate = item } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                    }
                } else {
                    Text(item.period.displayName)
                        .font(.designBodyCaption)
                        .foregroundStyle(.secondary)
                }
            }

            BudgetSpendingLine(label: "本期", spent: perSpent, budget: item.amount, currency: currency)
            BudgetSpendingLine(label: "累计", spent: cumSpent, budget: item.totalBudget, currency: currency)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = inside }
            if inside, item.category != nil {
                NSCursor.pointingHand.push()
            } else if !inside {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            if let cat = item.category { navCategory = cat }
            else { editingItem = item }
        }
    }
}
