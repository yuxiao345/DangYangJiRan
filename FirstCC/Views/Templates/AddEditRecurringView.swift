import SwiftUI
import SwiftData

enum RecurringPickerSheet: Identifiable {
    case account, toAccount, category, member, merchant, project
    var id: Self { self }
}

struct AddEditRecurringView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appContainer: AppContainer

    let editingRule: RecurringRule?
    let ledger: Ledger?
    private var effectiveLedger: Ledger? { ledger ?? appContainer.currentLedger }

    @State private var name: String = ""
    @State private var type: TransactionType = .expense
    @State private var amount: Decimal = 0
    @State private var note: String = ""
    @State private var selectedAccount: Account?
    @State private var selectedToAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedMember: Member?
    @State private var selectedMerchant: Merchant?
    @State private var selectedProject: Project?
    @State private var frequency: RecurringFrequency = .monthly
    @State private var interval: Int = 1
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 365)

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var members: [Member] = []
    @State private var merchants: [Merchant] = []
    @State private var projects: [Project] = []
    @State private var pickerSheet: RecurringPickerSheet?

    init(editing: RecurringRule? = nil, ledger: Ledger? = nil) {
        self.editingRule = editing
        self.ledger = ledger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) {
                        ForEach([TransactionType.expense, .income, .transfer], id: \.self) { t in
                            Label(t.displayName, systemImage: t.systemIcon).tag(t)
                        }
                    }
                }

                Section("金额") {
                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("账户") {
                    Button { openPicker(.account) } label: {
                        pickerRow(label: type == .transfer ? "转出账户" : "付款账户", value: selectedAccount?.name)
                    }
                    if type == .transfer {
                        Button { openPicker(.toAccount) } label: {
                            pickerRow(label: "转入账户", value: selectedToAccount?.name)
                        }
                    }
                }

                if type != .transfer {
                    Section("分类") {
                        Button { openPicker(.category) } label: {
                            pickerRow(label: "分类", value: selectedCategory?.name)
                        }
                    }
                }

                Section {
                    Picker("频率", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    Stepper("间隔: \(interval)", value: $interval, in: 1...99)
                        .foregroundStyle(interval > 1 ? .primary : .secondary)
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    Toggle("结束日期", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("截止日期", selection: $endDate, displayedComponents: .date)
                    }
                } header: {
                    Text("周期")
                } footer: {
                    Text(frequencyDescription)
                }

                if type != .transfer {
                    Section("更多信息") {
                        Button { openPicker(.member) } label: {
                            pickerRow(label: "成员", value: selectedMember?.name)
                        }
                        Button { openPicker(.merchant) } label: {
                            pickerRow(label: "商家", value: selectedMerchant?.name)
                        }
                        Button { openPicker(.project) } label: {
                            pickerRow(label: "项目", value: selectedProject?.name)
                        }
                    }
                }

                Section("备注") {
                    TextField("备注", text: $note)
                }
            }
            .navigationTitle(editingRule != nil ? "编辑周期账" : "新建周期账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(name.isEmpty)
                }
            }
            .task { loadData(); prefillEditing() }
            .onChange(of: type) { _, _ in loadCategories() }
            .onChange(of: pickerSheet) { _, newValue in
                if newValue != nil { loadData() }
            }
            .sheet(item: $pickerSheet) { sheet in
                switch sheet {
                case .account:
                    SearchablePickerView(
                        title: type == .transfer ? "转出账户" : "付款账户",
                        items: accounts,
                        itemLabel: { $0.name },
                        itemIcon: { $0.iconName ?? "creditcard" },
                        itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
                        recentKey: "recent_account",
                        selection: $selectedAccount
                    )
                case .toAccount:
                    SearchablePickerView(
                        title: "转入账户",
                        items: accounts.filter { $0.id != selectedAccount?.id },
                        itemLabel: { $0.name },
                        itemIcon: { $0.iconName ?? "creditcard" },
                        itemColor: { Color(hex: $0.colorHex ?? "#007AFF") },
                        recentKey: "recent_toaccount",
                        selection: $selectedToAccount
                    )
                case .category:
                    SearchablePickerView(
                        title: "选择分类",
                        items: categories,
                        itemLabel: { $0.name },
                        itemIcon: { $0.iconName },
                        itemColor: { Color(hex: $0.colorHex) },
                        recentKey: "recent_category",
                        selection: $selectedCategory
                    )
                case .member:
                    SearchablePickerView(
                        title: "选择成员",
                        items: members,
                        itemLabel: { $0.name },
                        itemIcon: { $0.avatar },
                        recentKey: "recent_member",
                        selection: $selectedMember
                    )
                case .merchant:
                    SearchablePickerView(
                        title: "选择商家",
                        items: merchants,
                        itemLabel: { $0.name },
                        itemIcon: { _ in "bag" },
                        recentKey: "recent_merchant",
                        selection: $selectedMerchant
                    )
                case .project:
                    SearchablePickerView(
                        title: "选择项目",
                        items: projects,
                        itemLabel: { $0.name },
                        itemIcon: { _ in "folder" },
                        recentKey: "recent_project",
                        selection: $selectedProject
                    )
                }
            }
        }
    }

    private var frequencyDescription: String {
        var desc = "每\(interval > 1 ? "\(interval)" : "")\(frequency.displayName)"
        if hasEndDate {
            desc += "，至\(endDate.formatted(date: .abbreviated, time: .omitted))止"
        }
        return desc
    }

    private func pickerRow(label: String, value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.designOnSurface)
            Spacer()
            if let value {
                Text(LocalizedStringKey(value)).foregroundStyle(.secondary)
            } else {
                Text("选择\(label)").foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func openPicker(_ sheet: RecurringPickerSheet) {
        loadData()
        pickerSheet = sheet
    }

    private func loadData() {
        guard let ledger = effectiveLedger else { return }
        accounts = (try? appContainer.accountService.fetchAccounts(for: ledger, context: modelContext)) ?? []
        loadCategories()
        members = (try? appContainer.memberService.fetchMembers(for: ledger, context: modelContext)) ?? []
        merchants = (try? appContainer.merchantService.fetchMerchants(for: ledger, context: modelContext)) ?? []
        projects = (try? appContainer.projectService.fetchProjects(for: ledger, context: modelContext)) ?? []
    }

    private func loadCategories() {
        guard let ledger = effectiveLedger else { return }
        categories = (try? appContainer.categoryService.fetchCategories(for: ledger, type: type, context: modelContext)) ?? []
    }

    private func prefillEditing() {
        guard let rule = editingRule, let t = rule.template else { return }
        name = t.name
        type = t.type
        amount = t.amount
        note = t.note ?? ""
        selectedAccount = t.account
        selectedToAccount = t.toAccount
        selectedCategory = t.category
        selectedMember = t.member
        selectedMerchant = t.merchant
        selectedProject = t.project
        frequency = rule.frequency
        interval = rule.interval
        startDate = rule.startDate
        if let end = rule.endDate {
            hasEndDate = true
            endDate = end
        }
    }

    private func save() {
        guard let ledger = effectiveLedger else { return }
        if let rule = editingRule, let t = rule.template {
            t.name = name
            t.type = type
            t.amount = amount
            t.note = note.isEmpty ? nil : note
            t.account = selectedAccount
            t.toAccount = selectedToAccount
            t.category = selectedCategory
            t.member = selectedMember
            t.merchant = selectedMerchant
            t.project = selectedProject
            try? appContainer.templateService.updateTemplate(t, context: modelContext)
            let end = hasEndDate ? endDate : nil
            try? appContainer.recurringService.setRecurring(
                template: t,
                frequency: frequency,
                interval: interval,
                startDate: startDate,
                endDate: end,
                context: modelContext
            )
        } else {
            let template = TransactionTemplate(
                name: name,
                type: type,
                amount: amount,
                note: note.isEmpty ? nil : note,
                account: selectedAccount,
                toAccount: selectedToAccount,
                category: selectedCategory,
                member: selectedMember,
                merchant: selectedMerchant,
                project: selectedProject
            )
            try? appContainer.templateService.createTemplate(template, ledger: ledger, context: modelContext)
            let end = hasEndDate ? endDate : nil
            try? appContainer.recurringService.setRecurring(
                template: template,
                frequency: frequency,
                interval: interval,
                startDate: startDate,
                endDate: end,
                context: modelContext
            )
        }
        dismiss()
    }
}
