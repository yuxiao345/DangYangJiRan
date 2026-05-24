import SwiftUI
@preconcurrency import CoreData

struct BudgetBookDetailView: View {
    @Environment(\.managedObjectContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer
    let book: BudgetBook
    @State private var items: [BudgetItem] = []
    @State private var showAddSheet = false
    @State private var editingItem: BudgetItem?
    @State private var cumulativeSpent: [UUID: Decimal] = [:]
    @State private var periodSpent: [UUID: Decimal] = [:]

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
                        .contentShape(Rectangle())
                        .onTapGesture { editingItem = item }
                        .swipeActions(edge: .leading) {
                            Button { editingItem = item } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                try? appContainer.budgetService.deleteItem(item, context: modelContext)
                                loadData()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
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
        .onAppear(perform: loadData)
    }

    private var summaryCard: some View {
        let totalBudget = appContainer.budgetService.totalBudget(for: book)
        let totalCumulative = appContainer.budgetService.totalCumulativeSpending(for: book, context: modelContext)
        let totalPeriod = appContainer.budgetService.totalCurrentPeriodSpending(for: book, context: modelContext)
        let periodBudget = appContainer.budgetService.totalCurrentPeriodBudget(for: book)
        let currency = book.ledger?.defaultCurrencyCode ?? "CNY"

        return VStack(spacing: 12) {
            budgetSummaryBlock(
                label: "本期支出",
                spent: totalPeriod,
                budget: periodBudget,
                currency: currency
            )
            Divider()
            budgetSummaryBlock(
                label: "累计支出",
                spent: totalCumulative,
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

    private func itemRow(_ item: BudgetItem) -> some View {
        let currency = book.ledger?.defaultCurrencyCode ?? "CNY"
        let cumSpent = cumulativeSpent[item.id] ?? 0
        let perSpent = periodSpent[item.id] ?? 0
        let totalBgt = item.totalBudget

        return VStack(alignment: .leading, spacing: 4) {
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

            // 本期
            budgetSpendingLine(
                label: "本期",
                spent: perSpent,
                budget: item.amount,
                currency: currency
            )
            // 累计
            budgetSpendingLine(
                label: "累计",
                spent: cumSpent,
                budget: totalBgt,
                currency: currency
            )
        }
        .padding(.vertical, 2)
    }

    private func budgetSpendingLine(label: String, spent: Decimal, budget: Decimal, currency: String) -> some View {
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
        if progress > 1.0 { return .red }
        switch progress {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .orange
        }
    }

    private func loadData() {
        items = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
        for item in items {
            cumulativeSpent[item.id] = appContainer.budgetService.cumulativeSpending(for: item, context: modelContext)
            periodSpent[item.id] = appContainer.budgetService.currentPeriodSpending(for: item, context: modelContext)
        }
    }
}
