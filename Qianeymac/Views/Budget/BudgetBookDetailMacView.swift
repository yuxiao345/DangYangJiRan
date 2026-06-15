import SwiftUI
@preconcurrency import CoreData

struct BudgetBookDetailMacView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    let book: BudgetBook
    @State private var items: [BudgetItem] = []
    @State private var cumulative: [UUID: Decimal] = [:]
    @State private var period: [UUID: Decimal] = [:]

    var body: some View {
        let currency = book.ledger?.defaultCurrencyCode ?? "CNY"
        let totalBudget = appContainer.budgetService.totalBudget(for: book)
        let totalCumulative = appContainer.budgetService.totalCumulativeSpending(for: book, context: modelContext)
        let totalPeriod = appContainer.budgetService.totalCurrentPeriodSpending(for: book, context: modelContext)
        let periodBudget = appContainer.budgetService.totalCurrentPeriodBudget(for: book)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 概览
                    VStack(spacing: 12) {
                        Text("概览").font(.designLabel)
                            .foregroundStyle(Color.designOnSurfaceVariant).tracking(1.0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        budgetLine(label: "本期支出", spent: totalPeriod, budget: periodBudget, currency: currency)
                        Divider().opacity(0.3)
                        budgetLine(label: "累计支出", spent: totalCumulative, budget: totalBudget, currency: currency)
                    }
                    .padding(16).glassCard(cornerRadius: 16)

                    // 预算项
                    if !items.isEmpty {
                        VStack(spacing: 12) {
                            Text("预算项").font(.designLabel)
                                .foregroundStyle(Color.designOnSurfaceVariant).tracking(1.0)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(items) { item in
                                budgetItemRow(item, currency: currency)
                                if item.id != items.last?.id { Divider().opacity(0.2) }
                            }
                        }
                        .padding(16).glassCard(cornerRadius: 16)
                    }
                }
                .padding(24)
            }
            .designScreen()
            .navigationTitle(book.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 500)
        .onAppear { loadData() }
    }

    private func loadData() {
        items = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
        for item in items {
            cumulative[item.id] = appContainer.budgetService.cumulativeSpending(for: item, context: modelContext)
            period[item.id] = appContainer.budgetService.currentPeriodSpending(for: item, context: modelContext)
        }
    }

    private func budgetLine(label: String, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.designBodyMedium)
                Spacer()
                CurrencyText(amount: spent, currencyCode: currency, size: 15, foregroundColor: ratio > 1.0 ? .red : Color.designOnSurface)
                Text("/").font(.designBodySmall).foregroundStyle(.secondary)
                CurrencyText(amount: budget, currencyCode: currency, size: 12, foregroundColor: .secondary)
                Text("\(Int(pct))%").font(.designBodySmall).foregroundStyle(progressColor(ratio))
            }
            if budget > 0 {
                PixelProgressBar(progress: min(ratio, 1.0), tint: progressColor(ratio))
            }
        }
    }

    private func budgetItemRow(_ item: BudgetItem, currency: String) -> some View {
        let cumSpent = cumulative[item.id] ?? 0
        let perSpent = period[item.id] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let cat = item.category {
                    Image(systemName: cat.iconName).foregroundStyle(Color(hex: cat.colorHex))
                    Text(LocalizedStringKey(cat.name)).font(.designBodySmall)
                } else {
                    Image(systemName: "chart.pie").foregroundStyle(Color.designPrimaryContainer)
                    Text("未分类").font(.designBodySmall)
                }
                Spacer()
                Text(item.period.displayName).font(.designBodyCaption).foregroundStyle(.secondary)
            }
            spendingLine(label: "本期", spent: perSpent, budget: item.amount, currency: currency)
            spendingLine(label: "累计", spent: cumSpent, budget: item.totalBudget, currency: currency)
        }
    }

    private func spendingLine(label: String, spent: Decimal, budget: Decimal, currency: String) -> some View {
        let ratio = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0
        let pct = ratio * 100
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.designBodySmall).foregroundStyle(.secondary)
                Spacer()
                CurrencyText(amount: spent, currencyCode: currency, size: 12, foregroundColor: ratio > 1.0 ? .red : Color.designOnSurface)
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

