import SwiftUI
@preconcurrency import CoreData

struct AddEditBudgetItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    let editing: BudgetItem?
    let book: BudgetBook
    let preselectedCategory: Category?
    private var effectiveLedger: Ledger? { book.ledger ?? appContainer.currentLedger }

    @State private var amount: Decimal = 0
    @State private var period: BudgetPeriod = .monthly
    @State private var alertThreshold: Double = 0.8
    @State private var isActive: Bool = true
    @State private var selectedCategory: Category?
    @State private var categories: [Category] = []
    @State private var showCategoryPicker = false
    @State private var categorySearchText = ""
    @State private var errorMessage: String?

    #if os(macOS)
    private let fieldLabel: Font = .custom("SpaceGrotesk-Regular", fixedSize: 13)
    #endif

    init(editing: BudgetItem? = nil, book: BudgetBook, preselectedCategory: Category? = nil) {
        self.editing = editing
        self.book = book
        self.preselectedCategory = preselectedCategory
    }

    var body: some View {
        NavigationStack {
            contentView
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
                } else if let cat = preselectedCategory {
                    selectedCategory = cat
                }
            }
            #if !os(macOS)
            .onChange(of: showCategoryPicker) { _, show in
                if show { loadCategories() }
            }
            .sheet(isPresented: $showCategoryPicker) {
                SearchablePickerView(
                    title: "选择分类",
                    items: categories,
                    itemLabel: { cat in
                        let cnt = (cat.children?.count ?? 0)
                        return cnt > 0 ? "\(cat.name) · 含\(cnt)项" : cat.name
                    },
                    itemIcon: { $0.iconName },
                    itemColor: { Color(hex: $0.colorHex) },
                    recentKey: "recent_budget_category",
                    indentLevel: { item in
                        var depth = 0; var p = item.parent; while p != nil { depth += 1; p = p?.parent }
                        return depth
                    },
                    childrenProvider: { Array($0.children ?? []) },
                    selection: $selectedCategory
                )
            }
            #endif
        }
        .alert(Text("提示"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text("该分类已存在预算项，不能重复添加")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 24) {
                categorySection
                budgetSettingsSection
                overviewSection
                if editing != nil { deleteSection }
            }
            .padding(24)
            .frame(minWidth: 400, maxWidth: 500)
        }
        .designScreen()
        #else
        Form {
            categorySection
            budgetSettingsSection
            overviewSection
            if editing != nil { deleteSection }
        }
        #endif
    }

    // MARK: - Sections

    private var categorySection: some View {
        Group {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    loadCategories()
                    showCategoryPicker = true
                } label: {
                    HStack {
                        Text("分类").font(fieldLabel).foregroundStyle(Color.designOnSurfaceVariant)
                        Spacer()
                        if let cat = selectedCategory {
                            Image(systemName: cat.iconName)
                                .foregroundStyle(Color(hex: cat.colorHex))
                            Text(LocalizedStringKey(cat.name))
                                .font(fieldLabel)
                        } else {
                            Text("未选择").font(fieldLabel).foregroundStyle(.secondary)
                        }
                        Image(systemName: showCategoryPicker ? "chevron.down" : "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.designOnSurfaceVariant.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if showCategoryPicker {
                    Divider()
                    if categories.isEmpty {
                        Text("加载中...").font(.designBodySmall).foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        TextField("搜索分类...", text: $categorySearchText)
                            .textFieldStyle(.plain)
                            .font(.designBodySmall)
                            .padding(.vertical, 4)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                Button {
                                    selectedCategory = nil
                                    showCategoryPicker = false
                                } label: {
                                    HStack {
                                        Text("清除选择").foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                let shown = categories.filter { categorySearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(categorySearchText) }
                                ForEach(shown) { cat in
                                    let depth = categoryDepth(cat)
                                    let hasChildren = (cat.children?.count ?? 0) > 0
                                    let isSelected = selectedCategory?.id == cat.id
                                    Button {
                                        selectedCategory = cat
                                        showCategoryPicker = false
                                    } label: {
                                        HStack {
                                            if depth > 0 {
                                                Color.clear.frame(width: CGFloat(depth) * 20)
                                            }
                                            Image(systemName: cat.iconName)
                                                .foregroundStyle(Color(hex: cat.colorHex))
                                                .frame(width: 24)
                                            Text(cat.name)
                                                .foregroundStyle(isSelected ? Color.designPrimaryContainer : .primary)
                                            if hasChildren {
                                                Text("· \(cat.children!.count)项")
                                                    .font(.designBodyCaption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Color.designPrimaryContainer)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
                if let cat = selectedCategory, (cat.children?.count ?? 0) > 0 {
                    Text("已选择上级分类「\(cat.name)」，可展开选择更具体的子分类")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(16).glassCard(cornerRadius: 12)
            #else
            Section("分类") {
                Button {
                    loadCategories()
                    showCategoryPicker = true
                } label: {
                    HStack {
                        Text("选择分类").foregroundStyle(Color.designOnSurface)
                        Spacer()
                        if let cat = selectedCategory {
                            Text(LocalizedStringKey(cat.name)).foregroundStyle(.secondary)
                        } else {
                            Text("选择分类").foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let cat = selectedCategory, (cat.children?.count ?? 0) > 0 {
                    Text("已选择上级分类「\(cat.name)」，可展开选择更具体的子分类")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            #endif
        }
    }

    private var budgetSettingsSection: some View {
        Group {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 16) {
                Text("预算设置").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)
                HStack {
                    Text("金额").font(fieldLabel).foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    NumpadAmountField(amount: $amount)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.designOnSurfaceVariant.opacity(0.25), lineWidth: 1)
                )
                HStack {
                    Text("周期").font(fieldLabel).foregroundStyle(Color.designOnSurfaceVariant)
                    Spacer()
                    Picker("", selection: $period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(fieldLabel)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.designOnSurfaceVariant.opacity(0.25), lineWidth: 1)
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("预警阈值").font(fieldLabel)
                        Spacer()
                        Text("\(Int(alertThreshold * 100))%")
                            .font(.designMonoDataSmall)
                            .foregroundStyle(Color.designOnSurfaceVariant)
                    }
                    Slider(value: $alertThreshold, in: 0.5...1.0, step: 0.05)
                }
                Toggle(isOn: $isActive) {
                    Text("启用").font(fieldLabel).foregroundStyle(Color.designOnSurfaceVariant)
                }
            }
            .padding(16).glassCard(cornerRadius: 12)
            #else
            Section("预算设置") {
                HStack {
                    Text("金额")
                    Spacer()
                    NumpadAmountField(amount: $amount)
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
            #endif
        }
    }

    private var overviewSection: some View {
        let count = periodCount
        let total = (amount as NSDecimalNumber).multiplying(by: NSDecimalNumber(value: count)) as Decimal
        return Group {
            #if os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                Text("预算概览").font(.designLabel).foregroundStyle(Color.designOnSurfaceVariant)
                HStack {
                    Text("期间数量").font(fieldLabel)
                    Spacer()
                    Text(String(format: count.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", count))
                        .font(fieldLabel)
                        .foregroundStyle(.secondary)
                    Text(periodUnit)
                        .font(fieldLabel)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("总预算").font(fieldLabel)
                    Spacer()
                    CurrencyText(amount: total, currencyCode: book.ledger?.defaultCurrencyCode ?? "CNY", size: 13, foregroundColor: Color.designPrimaryFixedDim)
                }
            }
            .padding(16).glassCard(cornerRadius: 12)
            #else
            Section("预算概览") {
                HStack {
                    Text("期间数量")
                    Spacer()
                    Text(String(format: count.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", count))
                        .foregroundStyle(.secondary)
                    Text(periodUnit)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("总预算")
                    Spacer()
                    CurrencyText(amount: total, currencyCode: book.ledger?.defaultCurrencyCode ?? "CNY", size: 17, foregroundColor: .blue)
                }
            }
            #endif
        }
    }

    private var deleteSection: some View {
        Group {
            #if os(macOS)
            Button(role: .destructive) { deleteItem() } label: {
                Label("删除预算项", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .padding(16).glassCard(cornerRadius: 12)
            #else
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
            #endif
        }
    }

    private var periodUnit: String {
        switch period {
        case .weekly: String(localized: "周")
        case .monthly: String(localized: "月")
        case .quarterly: String(localized: "季度")
        case .yearly: String(localized: "年")
        }
    }

    #if os(macOS)
    private func categoryDepth(_ cat: Category) -> Int {
        var depth = 0; var p = cat.parent; while p != nil { depth += 1; p = p?.parent }
        return depth
    }
    #endif

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
        guard let ledger = effectiveLedger else {
            NSLog("[BudgetItem] loadCategories: effectiveLedger nil, book.ledger=\(book.ledger?.name ?? "nil"), appContainer.currentLedger=\(appContainer.currentLedger?.name ?? "nil")")
            return
        }
        let fetched = (try? appContainer.categoryService.fetchAllCategories(for: ledger, type: .expense, context: modelContext)) ?? []
        NSLog("[BudgetItem] loadCategories: ledger=\(ledger.name) id=\(ledger.id), fetched \(fetched.count)")
        categories = fetched
    }

    private func deleteItem() {
        guard let item = editing else { return }
        try? appContainer.budgetService.deleteItem(item, context: modelContext)
        dismiss()
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        // 检查分类是否重复
        if let cat = selectedCategory {
            let existing = (try? appContainer.budgetService.fetchItems(for: book, context: modelContext)) ?? []
            if let dup = existing.first(where: { $0.category?.id == cat.id && $0.id != editing?.id }) {
                errorMessage = String(localized: "该分类已存在预算项，不能重复添加")
                return
            }
        }
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
