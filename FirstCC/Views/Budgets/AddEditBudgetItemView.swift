import SwiftUI
@preconcurrency import CoreData

struct AddEditBudgetItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let editing: BudgetItem?
    let book: BudgetBook
    private var effectiveLedger: Ledger? { book.ledger ?? appContainer.currentLedger }

    @State private var amount: Decimal = 0
    @State private var period: BudgetPeriod = .monthly
    @State private var alertThreshold: Double = 0.8
    @State private var isActive: Bool = true
    @State private var selectedCategory: Category?
    @State private var categories: [Category] = []

    init(editing: BudgetItem? = nil, book: BudgetBook) {
        self.editing = editing
        self.book = book
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    Picker("选择分类", selection: $selectedCategory) {
                        ForEach(categories.filter { $0.type == .expense }) { cat in
                            Label(LocalizedStringKey(cat.name), systemImage: cat.iconName)
                                .tag(cat as Category?)
                        }
                    }
                }
                Section("预算设置") {
                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    Picker("周期", selection: $period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("预警阈值: \(Int(alertThreshold * 100))%")
                            .font(.footnote)
                        Slider(value: $alertThreshold, in: 0.5...1.0, step: 0.05)
                    }
                    Toggle("启用", isOn: $isActive)
                }
                Section("预算概览") {
                    let count = periodCount
                    HStack {
                        Text("期间数量")
                        Spacer()
                        Text(String(format: count.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", count))
                            .foregroundStyle(.secondary)
                        Text(period.displayName)
                            .foregroundStyle(.secondary)
                    }
                    let total = (amount as NSDecimalNumber).multiplying(by: NSDecimalNumber(value: count)) as Decimal
                    HStack {
                        Text("总预算")
                        Spacer()
                        CurrencyText(amount: total, currencyCode: book.ledger?.defaultCurrencyCode ?? "CNY", size: 17, foregroundColor: .blue)
                    }
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteItem()
                        } label: {
                            HStack {
                                Spacer()
                                Label("删除预算项", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(editing != nil ? "编辑预算项" : "新建预算项")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(amount <= 0 || selectedCategory == nil)
                }
            }
            .onAppear {
                loadCategories()
                if let item = editing {
                    amount = item.amount
                    period = item.period
                    alertThreshold = item.alertThreshold
                    isActive = item.isActive
                    selectedCategory = item.category
                }
            }
        }
    }

    private var periodCount: Double {
        let days = Calendar.current.dateComponents([.day], from: book.startDate, to: book.endDate).day ?? 0
        let totalDays = Double(max(days, 1))
        switch period {
        case .weekly:
            return (totalDays / 7.0).rounded()
        case .monthly:
            return (totalDays / (365.25 / 12.0)).rounded()
        case .quarterly:
            let months = totalDays / (365.25 / 12.0)
            let quarters = months / 3.0
            return (quarters * 10).rounded() / 10.0
        case .yearly:
            let years = totalDays / 365.25
            return (years * 10).rounded() / 10.0
        }
    }

    private func loadCategories() {
        guard let ledger = effectiveLedger else { return }
        categories = (try? appContainer.categoryService.fetchAllCategories(for: ledger, type: .expense, context: modelContext)) ?? []
    }

    private func deleteItem() {
        guard let item = editing else { return }
        try? appContainer.budgetService.deleteItem(item, context: modelContext)
        dismiss()
    }

    private func save() {
        NSLog("[BudgetItem] save() entered")
        guard let ledger = effectiveLedger else { NSLog("[BudgetItem] no ledger, returning"); return }
        NSLog("[BudgetItem] ledger OK: \(ledger.name)")
        if let item = editing {
            item.amount = amount
            item.period = period
            item.alertThreshold = alertThreshold
            item.isActive = isActive
            item.category = selectedCategory
            try? appContainer.budgetService.updateItem(item, context: modelContext)
        } else {
            NSLog("[BudgetItem] creating new item, amount=\(amount)")
            let item = BudgetItem(
                amount: amount,
                period: period,
                alertThreshold: alertThreshold,
                isActive: isActive,
                category: selectedCategory,
                context: modelContext
            )
            NSLog("[BudgetItem] item created, calling createItem")
            do {
                try appContainer.budgetService.createItem(item, book: book, ledger: ledger, context: modelContext)
                NSLog("[BudgetItem] createItem succeeded")
            } catch {
                NSLog("[BudgetItem] createItem error: \(error)")
            }
        }
        NSLog("[BudgetItem] calling dismiss()")
        dismiss()
    }
}
